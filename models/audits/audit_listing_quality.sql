with listings as (

    select *
    from {{ ref('int_car_listings_mileage_quality') }}

),

ops_reviews as (

    select *
    from {{ source('craigslist', 'OPS_LISTING_REVIEW') }}

),

audited_listings as (

    select
        l.listing_id,
        l.listing_price,
        l.vin,
        l.make,
        l.model,
        l.year,
        l.mileage,
        l.fuel_type,
        l.transmission,
        l.drivetrain,
        l.exterior_color,
        l.vehicle_condition,
        l.title_status,
        l.posting_date,
        l.region,
        l.state,
        l.latitude,
        l.longitude,

        l.model_quality_status,
        l.price_quality_status,
        l.price_quality_reason,
        l.mileage_quality_status,

        -- Checks for missing VIN
        case
            when l.vin is null
              or trim(l.vin) = ''
            then 1
            else 0
        end as has_vin_issue,

        -- Checks for unresolved make
        case
            when l.make is null
              or trim(l.make) = ''
            then 1
            else 0
        end as has_make_issue,

        -- Checks for missing or invalid model
        case
            when l.model_quality_status <> 'accepted'
            then 1
            else 0
        end as has_model_issue,

        -- Checks for listing price issues
        case
            when l.price_quality_status <> 'accepted'
            then 1
            else 0
        end as has_price_issue,

        -- Checks for mileage issues
        case
            when l.mileage_quality_status <> 'accepted'
            then 1
            else 0
        end as has_mileage_issue,

        -- Defaults new audit records to pending.
        -- Existing Data Ops decisions are retained from the review table.
        coalesce(r.approval_status, 'pending') as approval_status,

        r.corrected_vin,
        r.corrected_make,
        r.corrected_model,
        r.corrected_listing_price,
        r.corrected_mileage,
        r.corrected_title_status,
        r.review_notes,
        r.reviewed_at

    from listings l

    left join ops_reviews r
        on l.listing_id = r.listing_id

)

select *
from audited_listings
where has_vin_issue = 1
   or has_make_issue = 1
   or has_model_issue = 1
   or has_price_issue = 1
   or has_mileage_issue = 1