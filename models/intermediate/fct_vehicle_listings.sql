select *
from {{ ref('int_car_listings_mileage_quality') }}
where vin is not null
   or trim(vin) <> ''