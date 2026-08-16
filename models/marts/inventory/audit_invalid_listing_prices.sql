select
    listing_id,
    listing_price,
    make,
    model,
    year,
    vehicle_condition,
    region,
    price_quality_status,
    price_quality_reason

from {{ ref('int_car_listings_price_quality') }}

where price_quality_status <> 'accepted'