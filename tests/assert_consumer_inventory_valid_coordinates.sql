/*
    Test: Ensure latitude and longitude are within valid ranges.

    Purpose:
    - Prevent invalid coordinates from affecting map visualizations.

    Expected result:
    - Returns zero rows.
*/

select
    listing_id,
    latitude,
    longitude

from {{ ref('mart_consumer_inventory') }}

where
    (
        latitude is not null
        and (latitude < -90 or latitude > 90)
    )
    or
    (
        longitude is not null
        and (longitude < -180 or longitude > 180)
    )