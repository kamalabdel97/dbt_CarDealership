/*
    Test: Ensure excluded title statuses are not present.

    Purpose:
    - Verify that listings with Missing, Parts Only, or Salvage titles
      are excluded from the consumer inventory.

    Expected result:
    - Returns zero rows.
*/

select
    listing_id,
    title_status

from {{ ref('stg_car_listings') }}

where title_status in (
    'Missing',
    'Parts Only',
    'Salvage'
)