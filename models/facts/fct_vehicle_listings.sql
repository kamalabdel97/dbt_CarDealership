with automatically_accepted as (

    select
        listing_id,
        listing_price,
        vin,
        make,
        model,
        year,
        mileage,
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
        'automated' as record_resolution

    from {{ ref('int_car_listings_mileage_quality') }}

    where price_quality_status = 'accepted'
      and mileage_quality_status = 'accepted'
      and model_quality_status = 'accepted'
      and vin is not null
      and trim(vin) <> ''
      and make is not null

),

reviewed_and_released as (

    select
        listing_id,
        listing_price,
        vin,
        make,
        model,
        year,
        mileage,
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
        approval_status as record_resolution

    from {{ ref('int_resolved_audit_listings') }}

    where vin is not null
      and trim(vin) <> ''
      and make is not null
      and (

            (
                approval_status = 'updated'
                and resolved_model_quality_status = 'accepted'
                and resolved_price_quality_status = 'accepted'
                and resolved_mileage_quality_status = 'accepted'
            )

          or

            (
                approval_status = 'approved'

                -- Human approval can override a suspicious
                -- automated threshold, but not structurally invalid values.
                and listing_price > 0
                and model is not null
                and trim(model) <> ''
                and mileage is not null
                and mileage >= 0
            )

      )

)

select *
from automatically_accepted

union all

select *
from reviewed_and_released