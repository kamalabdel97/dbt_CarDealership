with ranked_listings as (

    select
        *,
        row_number() over (
            partition by vin
            order by posting_date desc, listing_id desc
        ) as listing_rank

    from {{ ref('fct_vehicle_listings') }}

)

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
    record_resolution

from ranked_listings

where listing_rank = 1