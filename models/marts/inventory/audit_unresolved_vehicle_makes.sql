select
    listing_id,
    model,
    year,
    listing_price,
    region,
    state,
    posting_date,
    listing_url,

    -- Gives the reviewer a quick reason this row was sent to audit
    case
        when model is null then 'Model is missing'
        when regexp_like(model, '^[0-9]{4}$') then 'Model contains only a year'
        when regexp_like(model, '^[0-9]{4} ') then 'Model begins with a year'
        else 'Manufacturer could not be inferred'
    end as audit_reason

from {{ ref('int_car_listings_make_model_cleanup') }}

where make is null