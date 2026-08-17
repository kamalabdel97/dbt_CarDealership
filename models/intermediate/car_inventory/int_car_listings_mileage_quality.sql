with listings as (

    select *
    from {{ ref('int_car_listings_price_quality') }}

),

mileage_quality as (

    select
        *,

        case
            -- Mileage was not provided
            when mileage is null then 'missing'

            -- Negative mileage is not a valid odometer reading
            when mileage < 0 then 'invalid'

            -- Mileage at or above 1,000,000 is treated as suspicious
            -- based on profiling of the extreme upper tail of the dataset
            when mileage >= 999999 then 'suspicious'

            -- All remaining mileage values are considered acceptable
            else 'accepted'
        end as mileage_quality_status

    from listings

)

select *
from mileage_quality