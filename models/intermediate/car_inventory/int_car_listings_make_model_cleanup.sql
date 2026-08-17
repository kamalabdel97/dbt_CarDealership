with staging_listings as (

    select *

    from {{ ref('stg_car_listings') }}

),

manufacturers_seed as (

    select
        manufacturer

    from {{ ref('manufacturers') }}

),

cleaned_listings as (

    select
        staging_listings.* exclude (make, model),

        -- Keep the original make.
        -- If it is null, use the matched manufacturer.
        coalesce(
            staging_listings.make,
            manufacturers_seed.manufacturer
        ) as make,

        case
            -- If we repaired the make using the matched manufacturer,
            -- remove that manufacturer from the beginning of the model
            when staging_listings.make is null
             and manufacturers_seed.manufacturer is not null
            then trim(
                substr(
                    -- Start the substring immediately after
                    -- the matched manufacturer and its following space
                    staging_listings.model,
                    length(manufacturers_seed.manufacturer) + 2
                )
            )

            -- Otherwise, no repair is needed or possible,
            -- so keep the original model
            else staging_listings.model

        end as model

    from staging_listings

    -- Join a manufacturer only when the original make is missing
    left join manufacturers_seed
        on staging_listings.make is null

       -- Match when the model begins with a manufacturer from the seed
       and lower(staging_listings.model)
           like lower(manufacturers_seed.manufacturer) || ' %'

)

select
    cleaned_listings.*,

    case
        -- Model is missing
        when model is null
          or trim(model) = ''
        then 'missing'

        -- Obvious placeholder values
        when upper(trim(model)) in ('-', '--', '/', 'N/A', 'NA', 'NONE','UNKNOWN')
        then 'invalid'

        -- Obvious malformed values such as:
        -- $362.47...
        -- *Coming Soon*
        -- / Accord
        -- (300)
        when left(trim(model), 1) in ('$', '*', '/', '(')
        then 'invalid'

        -- Otherwise keep the model
        else 'accepted'

    end as model_quality_status

from cleaned_listings