select

    -- Identifier
    id as listing_id,

    -- Affordability
    price as listing_price,

    -- Vehicle characteristics
    initcap(replace(manufacturer, '-', ' ')) as make,
    initcap(model) as model,
    year,
    odometer as mileage,
    initcap(fuel) as fuel_type,
    initcap(transmission) as transmission,
    upper(drive) as drivetrain,
    initcap(replace(paint_color, '_', ' ')) as exterior_color,
    initcap(condition) as vehicle_condition,
    initcap(replace(title_status, '_', ' ')) as title_status,
    vin,

    -- Listing details
    description,
    image_url,
    posting_date,
    url as listing_url,

    -- Location
    initcap(region) as region,
    upper(state) as state,
    lat as latitude,
    long as longitude

from {{ source('craigslist', 'CARINVENTORY') }}