/*
    Test: Ensure all listings have a positive price.

    Purpose:
    - Prevent zero or negative-priced listings from appearing in the consumer inventory.

    Expected result:
    - Returns zero rows.
*/

select
    listing_id,
    listing_price
from {{ ref('mart_consumer_inventory') }}
where listing_price <= 0