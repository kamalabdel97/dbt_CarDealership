with reviewed_listings as (

    select *
    from {{ ref('audit_listing_quality') }}

    where approval_status in (
        'approved',
        'updated'
    )

),

resolved_values as (

    select
        listing_id,

        case
            when approval_status = 'updated'
            then coalesce(corrected_listing_price, listing_price)
            else listing_price
        end as listing_price,

        case
            when approval_status = 'updated'
            then coalesce(corrected_vin, vin)
            else vin
        end as vin,

        case
            when approval_status = 'updated'
            then coalesce(corrected_make, make)
            else make
        end as make,

        case
            when approval_status = 'updated'
            then coalesce(corrected_model, model)
            else model
        end as model,

        year,

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

        case
            when approval_status = 'updated'
            then coalesce(corrected_title_status, title_status)
            else title_status
        end as title_status,

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

        case
            when listing_price is null then 'missing'
            when listing_price <= 0 then 'invalid_nonpositive'
            when listing_price < 500 then 'suspiciously_low'
            when listing_price > 1000000 then 'suspiciously_high'
            else 'accepted'
        end as resolved_price_quality_status,

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