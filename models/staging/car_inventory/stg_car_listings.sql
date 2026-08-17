with source as (

    select *
    from {{ source('craigslist', 'CARINVENTORY') }}

),

staged as (

    select
        id as listing_id,
        price as listing_price,
        upper(vin) as vin,
        initcap(manufacturer) as make,
        initcap(model) as model,
        year,
        odometer as mileage,
        initcap(fuel) as fuel_type,
        initcap(transmission) as transmission,
        upper(drive) as drivetrain,
        initcap(paint_color) as exterior_color,
        initcap(condition) as vehicle_condition,
        initcap(title_status) as title_status,
        posting_date,
        initcap(region) as region,
        upper(state) as state,
        lat as latitude,
        long as longitude

    from source

)

select *
from staged

where title_status not in (
    'Missing',
    'Parts Only',
    'Salvage'
)