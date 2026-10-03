# Craigslist Vehicle Analytics Pipeline

I bought my first car at 25 and didn't do the interest math until I was already sitting in it. Running payment numbers while you're still shopping is a pain, so most people skip it until the paperwork is in front of them.

This is a Power BI dashboard that shows monthly payment, total interest, and amortization schedule for any vehicle in the inventory. It runs on a one-time snapshot of 350K+ Craigslist listings, cleaned through a Snowflake and dbt pipeline.

**Snowflake** for storage, **dbt** for transformation, quality classification, and testing, **Power BI** for consumer inventory and loan analysis.

<p align="center">
<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/db5a8d15-a95c-4249-b12d-7f177362272a" />
<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/9d1ee412-e347-481c-8e0d-362f6e75edda" />
<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/88ed116b-56ad-45e4-a048-20385283c065" />

</p>

**[View the live dashboard]([#](https://app.powerbi.com/groups/me/reports/6908c6f7-ad99-4c90-a26c-b6e4aeb8ee77/5f89551261b6c3a9004c?experience=power-bi&bookmarkGuid=9242c9ce98250d100ec7))**

## Why the pipeline exists

The calculator itself is arithmetic. Most of the work went into making sure the price it runs on can be trusted.

The raw listings arrived with problems that would each break the dashboard in a different way:

| Problem in the data | What it does to the dashboard |
|---|---|
| Asking prices of $0 or negative | Payment of $0 on a real car |
| Odometer readings in the millions | Vehicle looks worthless, or filters break |
| Missing manufacturer, make buried in the model name | Car can't be found by search |
| Same vehicle posted repeatedly at different prices | Which price is the real one? |
| Missing VIN | No way to tell two listings apart |

The obvious fix is to delete anything that looks wrong, but that throws away real cars. Some trucks legitimately have 600,000 miles. Some vehicles legitimately cost $150,000.

So the pipeline classifies records instead of deleting them. Records that pass the rules go straight through. Questionable ones get routed to a review queue where a reviewer can approve, correct, or reject them, and anything corrected is re-checked against the same rules before it's allowed back in.

There's no actual reviewer on this project. What's built is the machinery around one: a persistent review table in Snowflake that survives dbt rebuilds, the four decision states, and the logic that revalidates and reintegrates corrected records. A production version would add a review interface, access controls, and ownership.

<!-- TODO: add counts: total listings in, clean, flagged for review, rejected -->

## How it works

```
raw listings
     ↓
  staging          standardize columns, drop salvage/parts-only titles
     ↓
 intermediate      repair make/model, classify price, classify mileage
     ↓
   ┌─────────────┴─────────────┐
   ↓                           ↓
passes rules              flagged for review
   │                           ↓
   │                    approve / correct / reject
   │                           ↓
   │                    corrected records revalidated
   ↓                           ↓
   └─────────────┬─────────────┘
                 ↓
        fct_vehicle_listings      every valid listing, full history
                 ↓
      mart_consumer_inventory     latest valid listing per vehicle
                 ↓
             Power BI
```

Rejected records aren't deleted either. They're held in a quarantine model so there's a record of what was excluded and why.

## The models

| Model | Grain | What it does |
|---|---|---|
| `stg_car_listings` | one row per source listing | Renames raw columns. Permanently drops salvage, parts-only, and missing-title vehicles, which are out of scope for a consumer tool rather than a quality problem to review. |
| `int_car_listings_make_model_cleanup` | one row per listing | Recovers a missing make when it's sitting at the front of the model name (`Genesis G70 3.3T` becomes make `Genesis`, model `G70 3.3T`). The manufacturer list lives in a dbt seed rather than a hardcoded CASE. Misspellings like `Chevorlet` are left alone and sent to review. |
| `int_car_listings_price_quality` | one row per listing | Classifies price as accepted, missing, non-positive, suspiciously low, or suspiciously high. No statistical cutoff, since a $150K truck is unusual and real. |
| `int_car_listings_mileage_quality` | one row per listing | Same pattern. Flags at 999,999 miles to catch placeholder values rather than at 500K, because legitimate commercial vehicles run well past half a million. Missing mileage goes to review. |
| `audit_listing_quality` | one row per problematic listing | A single review queue rather than four. Flag columns show every issue on a listing at once. |
| `int_resolved_audit_listings` | one row per approved or corrected record | Applies reviewer corrections, then re-runs the quality rules on them. A human edit doesn't exempt a record from the checks. |
| `fct_vehicle_listings` | one row per accepted listing | Every valid listing, repeat postings included. `record_resolution` tracks how each row got in: automated, approved, or updated. |
| `mart_consumer_inventory` | one row per vehicle (VIN) | Latest valid listing per vehicle. If the newest posting has a $0 price, the last good listing stays visible until it's fixed. |
| `quarantine_rejected_listings` | one row per rejected listing | Kept out of the dashboard, kept on the record. |

### Materialization strategy

| Layer | Materialization | Why |
|---|---|---|
| staging | view | Source standardization |
| intermediate | view | Transformation and quality classification |
| audits | view | Reflects the current review state |
| facts | table | Persisted analytical listing history |
| marts | table | Persisted consumer-facing output |

The audit models are views on purpose. `audit_listing_quality` joins live listings against `OPS_LISTING_REVIEW`, which is a table a human writes to, so a reviewer's decision shows up in the queue the moment it's made, with no rebuild.

The fact and mart are tables, which means the opposite is also true. An approved or corrected listing doesn't reach `fct_vehicle_listings` or the dashboard until the next dbt run. Review happens immediately, but release happens on rebuild.

## Testing

Tests are written against each model's grain, since that's what breaks silently.

| Model | Test | What it proves |
|---|---|---|
| `stg_car_listings` | `listing_id` unique, not null | Source arrives at listing grain |
| `fct_vehicle_listings` | `listing_id` unique, not null | No listing enters the fact twice, even though records arrive from two branches |
| `fct_vehicle_listings` | `listing_price`, `vin`, `make`, `mileage` not null | The four fields the acceptance rules require are actually present |
| `fct_vehicle_listings` | `record_resolution` in `automated`, `approved`, `updated` | Every row can account for how it got in |
| `mart_consumer_inventory` | `vin` unique, not null | One row per physical vehicle, which is the mart's entire contract |

Three singular tests assert business rules rather than column properties:

- `assert_consumer_inventory_positive_price` checks that no $0 or negative prices reach the dashboard
- `assert_consumer_inventory_valid_coordinates` checks that latitude and longitude stay in range, so map visuals don't break
- `assert_staging_excludes_title_status` checks that salvage, parts-only, and missing-title vehicles are dropped at staging

The `unique` test on `fct_vehicle_listings.listing_id` is the most important one. That model is a `union all` of automatically accepted listings and reviewer-released ones. If the branch conditions ever overlap, say a listing satisfies both the automated rules and an `approved` review decision, the same car would appear twice with two different `record_resolution` values, and nothing else in the pipeline would catch it.

## Running this yourself

This was built in dbt Cloud against Snowflake, so reproducing it requires your own accounts for both. The models, seeds, and setup SQL are all here, but the connection configuration is environment-specific.

<!-- TODO: verify these steps before publishing -->

**Prerequisites**
- Snowflake account
- dbt Cloud account
- Power BI Desktop

**Setup**

1. Fork or clone this repo
   ```bash
   git clone <!-- TODO: repo url -->
   ```

2. Load the Craigslist dataset into `CRAIGSLIST_DB.PUBLIC.CARINVENTORY`
   <!-- TODO: dataset link and row count -->

3. Create the operations review table in `CRAIGSLIST_DB.PUBLIC`

   This table lives outside dbt on purpose. Review decisions are human input, and
   dbt rebuilds its own models, so anything dbt owned would be wiped on the next run.
   It's declared as a dbt source so the audit models can read it.

   ```sql
   create table if not exists OPS_LISTING_REVIEW (
       listing_id number,
       approval_status varchar default 'pending',

       corrected_vin varchar,
       corrected_make varchar,
       corrected_model varchar,
       corrected_listing_price number,
       corrected_mileage number,
       corrected_title_status varchar,

       review_notes varchar,
       reviewed_at timestamp_ntz
   );
   ```

   `approval_status` drives the review workflow:

   | Status | Meaning |
   |---|---|
   | `pending` | Flagged, no decision yet. Stays out of the fact. |
   | `approved` | Reviewer confirmed the flagged value is legitimate. Released. |
   | `updated` | Reviewer supplied corrected values. Revalidated, then released if it passes. |
   | `rejected` | Excluded for good, retained in quarantine for traceability. |

4. Connect the repo to a dbt Cloud project pointed at your Snowflake connection

5. Build the pipeline
   ```bash
   dbt seed
   dbt run
   dbt test
   ```

6. Open the dashboard and repoint it at your Snowflake connection
   <!-- TODO: .pbix path in repo -->

## What this pipeline can't do

**Some makes can't be recovered.** The seed lookup repairs a missing manufacturer only when it sits at the front of the model name. Misspellings (`Chevorlet`), models with no make attached (`Grand Caravan`), and junk values (`Series`, `2011`) are left unresolved and sent to review.

**Listings without a VIN don't make it in.** VIN is how the pipeline knows two postings describe the same car. Without one, a listing can't be deduplicated or shown in inventory, so it's treated as a quality issue.

**Repeat listings are advertised prices, not price changes.** `fct_vehicle_listings` keeps every posting for a VIN, and some of those prices bounce around over short windows because of reposts, syndication, or multiple ads for one car. The fact preserves what was advertised and when. It doesn't prove a seller lowered their price.

**The inventory is historical, not live.** The latest valid listing for a VIN is the most recent one in this dataset. It says nothing about whether the car is still for sale.

**There's no real reviewer.** The review table, decision states, and revalidation logic all work, but the human is hypothetical. Production would need an interface, access controls, and someone who owns the queue.

**This is a static pipeline.** The dataset is a historical snapshot loaded into Snowflake once. There's no ingestion layer, no scheduled refresh, and no incremental logic, so every `dbt run` rebuilds from the same source table. The models are built at listing grain with a fact and mart split, so incremental materialization and a scheduled job could be added later without redesigning them.

**Price and mileage rules are duplicated.** The quality thresholds appear once in the intermediate models and again in `int_resolved_audit_listings`, which re-checks corrected values. They've already drifted apart once. A macro would define each rule in one place and call it from both, which is the next refactor.
