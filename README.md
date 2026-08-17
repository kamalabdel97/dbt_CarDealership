# Craigslist Vehicle Analytics Engineering Project

## Project Overview

This project transforms a historical Craigslist vehicle listings dataset into a cleaner, more reliable analytical dataset using **Snowflake**, **dbt**, and **Power BI**.

The source data contains several real-world data quality problems, including:

- missing manufacturers
- make values embedded inside model names
- invalid or suspicious prices
- implausible mileage values
- missing VINs
- repeated listings for the same VIN
- records that should not be shown in consumer-facing inventory

The goal of the project is to preserve useful vehicle listing history while preventing known bad records from reaching the final consumer inventory.

The pipeline also includes a theoretical Data Operations review process so questionable records can be reviewed, corrected, approved, or rejected instead of simply being deleted.

---

## Technology Stack

- **Snowflake** — data storage and persistent Operations review table
- **dbt** — transformation, data quality classification, lineage, and documentation
- **SQL** — transformation and business-rule logic
- **Power BI** — consumer inventory, affordability analysis, and reporting
- **dbt seeds** — manufacturer reference data used during make/model cleanup

---

# Prerequisite: Operations Review Table

Before the audit and review workflow can operate, a persistent writable table must exist in Snowflake.

This table is kept outside dbt because human review decisions need to remain stored even when dbt models are rebuilt.

Example:

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

The table is also declared as a dbt source so the audit models can connect automated quality findings with any existing Operations decisions.

Supported review statuses:

```text
pending   → waiting for review
approved  → flagged value was reviewed and confirmed as valid
updated   → Operations supplied one or more corrected values
rejected  → listing should remain excluded from analytics
```

The separation is intentional:

```text
dbt
→ identifies questionable records

OPS_LISTING_REVIEW
→ stores the human decision
```

---

# Pipeline Overview

```text
Raw vehicle listings
        ↓
stg_car_listings
        ↓
int_car_listings_make_model_cleanup
        ↑
 manufacturers seed
        ↓
int_car_listings_price_quality
        ↓
int_car_listings_mileage_quality
        │
        ├──────────────→ audit_listing_quality
        │                     ↑
        │              OPS_LISTING_REVIEW
        │                     ↓
        │          int_resolved_audit_listings
        │                     │
        │                     └─────────────┐
        │                                   │
        └──── automatically accepted ───────┤
                                            ↓
                                 fct_vehicle_listings
                                            ↓
                                 mart_consumer_inventory

Rejected review decisions
        ↓
quarantine_rejected_listings
```

## Pipeline Flow in Plain English

The raw vehicle listings first go through basic cleanup so the column names and values are easier to work with.

Next, the pipeline attempts to repair make and model information when the correct answer can be determined confidently.

After that, prices and mileage values are checked for obvious problems. These checks do not immediately delete questionable records. Instead, each record is classified so the pipeline knows whether it can be accepted automatically or needs review.

Listings that pass the automated rules are allowed into the historical vehicle listing table.

Listings with reviewable problems are sent to one audit queue. A Data Operations user could then:

- approve the original value
- provide a corrected value
- reject the listing
- leave it pending for later review

Approved or successfully corrected listings are allowed back into the historical listing table.

Rejected listings remain outside the analytical dataset but are retained separately for traceability.

Finally, the consumer inventory keeps only the latest valid listing for each VIN. If a newer listing is bad, the previous valid listing remains the consumer-facing record until the newer one is corrected or approved.

---

# Source Grain and Repeated VINs

The original dataset is listing-level data.

```text
listing_id = identifies one Craigslist listing
vin        = identifies the physical vehicle
```

A single VIN can therefore appear in multiple listings.

For example:

```text
VIN ABC123
├── September listing
├── October listing
└── November listing
```

These repeated VINs are intentionally preserved because they represent separate listing observations.

They are not automatically treated as duplicate records.

---

# Model Responsibilities

## `stg_car_listings`

**Grain:** one row per source listing.

The staging model standardizes the raw fields into cleaner, consistent names.

The staging model standardizes the raw source columns using aliases like:

```sql
select
    id as listing_id,
    price as listing_price,
    vin,
    manufacturer as make,
    model,
    year,
    odometer as mileage,
    fuel as fuel_type,
    transmission,
    drive as drivetrain,
    paint_color as exterior_color,
    condition as vehicle_condition,
    title_status,
    posting_date,
    region,
    state,
    lat as latitude,
    long as longitude
```

The staging model also removes title statuses that the project does not want anywhere in the downstream analytical dataset:

```text
Missing
Parts Only
Salvage
```

These are treated as permanent exclusions rather than records that need Operations review.

---

## `manufacturers` Seed

The manufacturer seed is reference data used to repair listings where `make` is missing but the manufacturer appears at the beginning of `model`.

Example source record:

```text
make  = NULL
model = Genesis G70 3.3T Sedan
```

Using the manufacturer seed, the pipeline can produce:

```text
make  = Genesis
model = G70 3.3T Sedan
```

Using a seed keeps the logic maintainable and avoids a large hardcoded manufacturer `CASE` statement.

---

## `int_car_listings_make_model_cleanup`

**Grain:** one row per listing.

This model repairs make/model combinations when the correct answer can be determined confidently.

The general rule is:

```text
If make already exists
→ keep it

If make is missing
and model begins with a recognized manufacturer
→ populate make
→ remove the manufacturer name from model

If the answer is unclear
→ leave the value unresolved
```

### Limitation

The model deliberately avoids guessing.

Examples such as:

```text
Chevorlet Impala
Nisaan Altima
Olet Silverado
Grand Caravan
Series
2011
```

may still require additional mappings or human review.

The project favors a conservative rule:

> Automatically repair what can be identified confidently and avoid inventing values when the source is ambiguous.

---

## `int_car_listings_price_quality`

**Grain:** one row per listing.

This model classifies listing prices.

Current logic:

```sql
case
    when listing_price is null then 'missing'
    when listing_price <= 0 then 'invalid_nonpositive'
    when listing_price < 500 then 'suspiciously_low'
    when listing_price > 1000000 then 'suspiciously_high'
    else 'accepted'
end as price_quality_status
```

A separate reason field explains why the record was classified that way.

### Why a simple statistical cutoff was not used

The dataset contains legitimately expensive vehicles and commercial vehicles.

A price can be statistically unusual without being wrong.

For that reason, the project does not treat every outlier as invalid.

Instead, the price rules focus on values that are clearly questionable for the intended consumer inventory.

---

## `int_car_listings_mileage_quality`

**Grain:** one row per listing.

Mileage profiling showed extreme values reaching into the millions.

However, inspection also showed legitimate-looking commercial vehicles with mileage well above 500,000.

Using 500,000 as a hard cutoff would therefore remove valid truck listings.

The project uses a more conservative rule:

```sql
case
    when mileage is null then 'missing'
    when mileage < 0 then 'invalid'
    when mileage >= 1000000 then 'suspicious'
    else 'accepted'
end as mileage_quality_status
```

This isolates the most extreme values without aggressively removing legitimate high-mileage commercial vehicles.

The quality model still labels null mileage as `missing` so the original data-quality condition is preserved. However, missing mileage is no longer considered sufficient for automatic inclusion in `fct_vehicle_listings`.

For the analytical fact, mileage must be present and accepted. A listing with missing mileage is treated as a reviewable issue rather than being automatically released.

---

# Unified Audit Workflow

## `audit_listing_quality`

**Grain:** one row per problematic listing.

Instead of creating separate operational files for:

- missing VIN
- unresolved make
- price issues
- mileage issues

the project consolidates them into one review queue.

Example issue fields:

```text
has_vin_issue
has_make_issue
has_price_issue
has_mileage_issue
```

For mileage, anything other than `accepted` is treated as an issue for this workflow. That includes:

```text
missing
invalid
suspicious
```

This matches the current fact-table rule that automatically accepted listings must contain usable mileage.

A listing can have more than one issue while still appearing only once in the audit table.

Example:

| listing_id | has_vin_issue | has_make_issue | has_price_issue | has_mileage_issue |
|---|---:|---:|---:|---:|
| 12345 | 0 | 1 | 1 | 0 |

This tells Operations exactly what is wrong with the listing without requiring them to search across several audit tables.

If a matching decision does not already exist in `OPS_LISTING_REVIEW`, the audit record defaults to:

```text
approval_status = pending
```

---

# Operations Review Decisions

The theoretical review process supports four outcomes.

## `pending`

The listing has been flagged but no decision has been made yet.

It remains outside the analytical fact.

---

## `approved`

Operations confirms that the original flagged value is legitimate.

Example:

```text
Automated result:
price is suspiciously high

Operations review:
the vehicle is legitimately expensive

Decision:
approved
```

The original record can then be released into the fact.

---

## `updated`

Operations provides corrected values.

Example:

```text
Original price: $0
Corrected price: $22,000
Decision: updated
```

The corrected values are checked again against the quality rules before the record is allowed into the fact.

---

## `rejected`

Operations determines that the listing should not be used.

It remains outside the fact and consumer inventory.

The record is retained separately so there is still a history of what was rejected and why.

---

# `int_resolved_audit_listings`

**Grain:** one row per approved or updated audit record.

This model prepares reviewed records for reintegration.

For an `updated` record, the corrected values replace the original values where supplied.

The corrected price and mileage are then reclassified.

Conceptually:

```text
record fails automated checks
        ↓
Operations updates it
        ↓
corrected values applied
        ↓
quality rules run again
        ↓
if valid → release to fact
```

This prevents a manually edited record from bypassing the project's quality rules simply because someone changed it.

---

# `fct_vehicle_listings`

**Grain:** one row per accepted listing ID.

This model contains the valid historical listing observations.

Two groups of records can enter:

```text
1. listings that passed automatically
2. listings that were approved or successfully corrected
```

For automatic acceptance, a listing must have:

```text
accepted price
accepted mileage
usable VIN
resolved make
```

Missing mileage does not enter the fact automatically.

For an `updated` audit record, the corrected price and mileage are rechecked and both must pass the applicable quality rules before the listing is released.

An `approved` record can be used as a human override for a value that was automatically classified as suspicious, but it still cannot contain structurally unusable values such as a missing VIN, missing make, nonpositive price, missing mileage, or negative mileage.

Conceptually:

```sql
automatically accepted listings

union all

reviewed and released listings
```

The model also includes `record_resolution`, which identifies how the record entered the fact:

```text
automated
approved
updated
```

---

## Why Multiple Listings for the Same VIN Stay in the Fact

The fact intentionally preserves repeated VINs.

Example:

```text
VIN ABC123

September → $25,000
October   → $24,000
November  → $22,500
```

This means the data model is capable of supporting future analysis such as:

- number of listings for a VIN
- average advertised price
- minimum advertised price
- maximum advertised price
- first observed price
- latest observed price
- advertised prices across posting dates

### Important Current-State Note

The current Power BI implementation does **not** yet use `fct_vehicle_listings` as a separate related model for historical advertised-price analysis.

There is currently no Power BI one-to-many VIN relationship or price-over-time visual built from this fact table.

The fact is intentionally modeled at listing grain so that this analysis can be added later without redesigning the dbt pipeline.

The current Power BI experience is centered on the consumer inventory mart.

---

## Historical Pricing Limitation

The project does not claim that repeated listings represent a perfect sequence of confirmed seller price changes.

During profiling, some VINs showed prices alternating between values over short periods.

Possible explanations include:

- reposting
- multiple advertisements
- dealer syndication
- other source behavior that is not captured in the dataset

For that reason, the project describes the fact as preserving:

> **historical advertised-price observations**

rather than confirmed vehicle price-change events.

---

# `mart_consumer_inventory`

**Grain:** one row per VIN.

This is the current primary dataset used by the Power BI consumer-facing experience.

The mart selects the latest valid listing from `fct_vehicle_listings` for each VIN.

Core logic:

```sql
row_number() over (
    partition by vin
    order by posting_date desc, listing_id desc
) as listing_rank
```

and keeps:

```sql
where listing_rank = 1
```

This creates a **last known good listing** strategy.

---

## Example: Newest Listing Has a Bad Price

Suppose one VIN has:

| Month | Price | Result |
|---|---:|---|
| September | $25,000 | Accepted |
| October | $24,000 | Accepted |
| November | $0 | Invalid |

Initially:

```text
fct_vehicle_listings
├── September → $25,000
└── October   → $24,000
```

November goes to the audit queue.

The consumer inventory continues to show:

```text
October → $24,000
```

because it is the latest valid record.

If Operations later corrects November to `$22,000`:

```text
November
→ corrected
→ revalidated
→ enters fact
```

the fact becomes:

```text
September → $25,000
October   → $24,000
November  → $22,000
```

and the consumer inventory automatically changes to:

```text
November → $22,000
```

because November is now the latest valid listing.

---

# `quarantine_rejected_listings`

Rejected listings are not physically deleted from the review workflow.

Records with:

```text
approval_status = rejected
```

are retained separately.

This acts like a controlled junk folder:

```text
rejected
→ not in historical fact
→ not in consumer inventory
→ still available for traceability
```

This keeps rejected records from contaminating downstream reporting while preserving a record of the decision.

---

# Current Power BI Usage

The Power BI dashboard currently uses the consumer inventory mart as its primary vehicle dataset.

This supports:

- vehicle filtering
- latest valid advertised price
- make/model selection
- mileage filtering
- geographic attributes
- vehicle affordability calculations
- loan calculations

The dbt project also produces `fct_vehicle_listings`, but the historical listing fact has **not yet been connected as a separate one-to-many Power BI model**.

That is a future extension rather than a completed dashboard feature.

A future Power BI model could use:

```text
mart_consumer_inventory
        1
        │ VIN
        │
        ∞
fct_vehicle_listings
```

to support historical advertised-price analysis for the selected vehicle.

The key point is that the dbt pipeline already preserves the necessary listing history even though the current report does not yet visualize it.

---

# Known Limitations and Workarounds

## Make/model quality

Some manufacturer information can be recovered from the model field using a controlled manufacturer reference list.

Ambiguous and misspelled values cannot always be corrected safely.

**Workaround:** automatically repair only deterministic matches and send unresolved reviewable cases through the audit process.

---

## Price outliers

The dataset contains both obvious bad values and legitimately expensive vehicles.

A simple statistical outlier cutoff would remove valid records.

**Workaround:** use broad business-rule classifications and allow human approval for legitimate exceptions.

---

## Mileage quality

Some extreme mileage values are clearly suspicious, but high mileage is legitimate for commercial vehicles. Missing mileage is also a problem for the current consumer-ready fact because mileage is an important vehicle attribute in the downstream experience.

**Workaround:** use a conservative million-mile threshold for suspicious values, preserve `missing` as a separate quality status, and require `accepted` mileage for automatic entry into `fct_vehicle_listings`. Missing, invalid, or suspicious mileage is handled through the review workflow rather than automatically entering the fact.

---

## Missing VINs

A VIN is needed to confidently connect multiple listings to the same physical vehicle.

**Workaround:** listings without a usable VIN do not enter the VIN-based fact or consumer inventory and are treated as reviewable quality issues.

---

## Repeated VINs

The same vehicle may appear in many listings.

These are not automatically duplicates because each listing has its own listing ID and posting date.

**Workaround:** preserve repeated VINs in the historical fact while reducing the consumer inventory to one latest valid listing per VIN.

---

## Historical pricing interpretation

Repeated listings do not prove that every price difference represents a confirmed seller price change.

**Workaround:** describe the data as historical advertised-price observations rather than confirmed price-change history.

---

## Consumer inventory freshness

The dataset is historical and does not prove whether a vehicle remained available after its latest observed posting.

**Workaround:** the mart represents the latest valid observation available in the dataset, not guaranteed real-time inventory availability.

---

## Human review workflow

The Operations review process is demonstrated through a persistent review table and dbt logic.

A production implementation would require an actual review interface, access controls, and clear ownership.

**Workaround for the portfolio project:** model the review states and reintegration logic in Snowflake/dbt to demonstrate how the workflow would operate.

---

# Project Takeaway

This project is about turning messy vehicle listings into data that is safer and easier to use.

Rather than deleting anything that looks unusual, the pipeline first tries to understand whether the record can be trusted.

Some problems can be fixed automatically. Others are set aside for review. Records that pass the checks are kept as part of the vehicle's listing history, while the consumer inventory only shows the most recent valid listing for each vehicle.

The result is a pipeline that keeps useful history, avoids showing obvious bad data, and still provides a path for questionable records to be corrected and returned to the dataset.

It also leaves room for the project to grow. The historical listing fact already exists, so future Power BI work can add vehicle-level advertised-price history without rebuilding the underlying dbt model.
