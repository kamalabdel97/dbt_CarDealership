with listings as (

    select *
    from {{ ref('int_car_listings_make_model_cleanup') }}

),

classified as (

    select
        *,

        case
            when listing_price is null then 'missing'
            when listing_price <= 0 then 'invalid_nonpositive'
            when listing_price < 500 then 'suspiciously_low'
            when listing_price > 1000000 then 'suspiciously_high'
            else 'accepted'
        end as price_quality_status,

        case
            when listing_price is null then 'Listing price is missing'
            when listing_price <= 0 then 'Price is zero or negative'
            when listing_price < 500 then 'Price is below consumer inventory threshold'
            when listing_price > 1000000 then 'Price exceeds plausible marketplace threshold'
        end as price_quality_reason

    from listings

)

select *
from classified