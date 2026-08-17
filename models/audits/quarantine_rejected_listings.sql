select *
from {{ ref('audit_listing_quality') }}

where approval_status = 'rejected'