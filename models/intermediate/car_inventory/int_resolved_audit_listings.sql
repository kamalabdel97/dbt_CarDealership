with reviewed_listings as (

    select *
    from {{ ref('audit_listing_quality') }}
    where approval_status in ('approved', 'updated')

),

resolved_values as (

    select
        listing_id,

        -- If Data Ops updated the price, use the corrected value.
        -- Otherwise, keep the original listing price.
        case
            when approval_status = 'updated'
            then coalesce(corrected_listing_price, listing_price)
            else listing_price
        end as listing_price,

        -- If Data Ops updated the VIN, use the corrected value.
        -- Otherwise, keep the original VIN.
        case
            when approval_status = 'updated'
            then coalesce(corrected_vin, vin)
            else vin
        end as vin,

        -- If Data Ops updated the make, use the corrected value.
        -- Otherwise, keep the original make.
        case
            when approval_status = 'updated'
            then coalesce(corrected_make, make)
            else make
        end as make,

        -- If Data Ops updated the model, use the corrected value.
        -- Otherwise, keep the original model.
        case
            when approval_status = 'updated'
            then coalesce(corrected_model, model)
            else model
        end as model,

        year,

        -- If Data Ops updated the mileage, use the corrected value.
        -- Otherwise, keep the original mileage.
        case
            when approval_status = 'updated'
            then coalesce(corrected_mileage, mileage)
            else mileage
        end as mileage,

        fuel_type,
        transmission,
        drivetrain,
        exterior_color,
        vehicle_condition,
        title_status,
        posting_date,
        region,
        state,
        latitude,
        longitude,

        approval_status,
        review_notes,
        reviewed_at

    from reviewed_listings

),

reclassified as (

    select
        *,

        -- Recheck the resolved model value.
        case
            when model is null
              or trim(model) = ''
            then 'missing'

            -- Obvious placeholder values
            when upper(trim(model)) in ('-', '--', '/', 'N/A', 'NA', 'NONE', 'UNKNOWN')
            then 'invalid'

            -- Obvious malformed values such as:
            -- $362.47...
            -- *Coming Soon*
            -- / Accord
            -- (300)
            when left(trim(model), 1) in ('$', '*', '/','(')
            then 'invalid'

            else 'accepted'
        end as resolved_model_quality_status,

        -- Recheck the resolved listing price.
        case
            when listing_price is null then 'missing'
            when listing_price <= 0 then 'invalid_nonpositive'
            when listing_price < 500 then 'suspiciously_low'
            when listing_price > 1000000 then 'suspiciously_high'
            else 'accepted'
        end as resolved_price_quality_status,

        -- Recheck the resolved mileage.
        case
            when mileage is null then 'missing'
            when mileage < 0 then 'invalid'
            when mileage >= 1000000 then 'suspicious'
            else 'accepted'
        end as resolved_mileage_quality_status

    from resolved_values

)

select *
from reclassified