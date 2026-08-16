with eligible_listings as (

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
        longitude

    from {{ ref('fct_vehicle_listings') }}

    where price_quality_status = 'accepted'
      and mileage_quality_status in ('accepted', 'missing')
      and make is not null
      and title_status not in (
          'Missing',
          'Parts Only',
          'Salvage'
      )

),

ranked_listings as (

    select
        *,
        row_number() over (
            partition by vin
            order by posting_date desc, listing_id desc
        ) as listing_rank

    from eligible_listings

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
    longitude

from ranked_listings

where listing_rank = 1