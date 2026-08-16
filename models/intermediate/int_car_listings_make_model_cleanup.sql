with staging_listings as (

    select *


    from {{ ref('stg_car_listings') }}

),

manufacturers_seed as (

    select
        manufacturer

    from {{ ref('manufacturers') }}

)

select
    staging_listings.* exclude (make, model),
    coalesce(staging_listings.make, manufacturers_seed.manufacturer) as make, -- Keep the original make, if it is null, use the matched manufacturer
    case
        -- If we repaired the make using the matched manufacturer,
        -- remove that manufacturer from the beginning of the model
        when staging_listings.make is null and manufacturers_seed.manufacturer is not null
        then trim(
            substr(
               -- Start the substring immediately after the matched manufacturer and its following space
                staging_listings.model,
                length(manufacturers_seed.manufacturer) + 2
            )
        )
    -- Otherwise, no repair is needed or possible, so keep the original model
        else staging_listings.model
    end as model

from staging_listings

-- Join a manufacturer only when the original make is missing
left join manufacturers_seed
    on staging_listings.make is null
    -- Match when the model begins with a manufacturer from the seed
   and lower(staging_listings.model)
       like lower(manufacturers_seed.manufacturer) || ' %'
