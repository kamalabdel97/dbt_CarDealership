/*
    Test: Ensure excluded title statuses are not present.

    Purpose:
    - Verify that listings with Missing, Parts Only, or Salvage titles are excluded.

    Expected result:
    - Returns zero rows.
*/

select
    listing_id,
    title_status

from {{ ref('mart_consumer_inventory') }}

where title_status in (
    'Missing',
    'Parts Only',
    'Salvage'
)