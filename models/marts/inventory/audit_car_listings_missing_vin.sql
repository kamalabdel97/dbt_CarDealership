select *
from {{ ref('int_car_listings_price_quality') }}
where vin is null
   or trim(vin) = ''