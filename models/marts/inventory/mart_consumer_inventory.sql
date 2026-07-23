select

    listing_id,
    listing_price,
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
    vin,
    description,
    image_url,
    posting_date,
    listing_url,
    region,
    state,
    latitude,
    longitude

from {{ ref('stg_car_listings') }}

where listing_price > 0
  and title_status not in (
      'Missing',
      'Parts Only',
      'Salvage'
  )