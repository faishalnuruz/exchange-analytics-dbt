-- A submission is loaded once as pending and again when reviewed. Keep the newest version.
select
    submission_id,
    cast(user_id as bigint) as user_id,
    cast(attempt_number as integer) as attempt_number,
    document_type,
    status as kyc_status,
    rejection_reason,
    cast(submitted_at as timestamp) as submitted_at,
    cast(reviewed_at as timestamp) as reviewed_at
from {{ source('app', 'kyc_submissions') }}
qualify row_number() over (
    partition by submission_id
    order by cast(updated_at as timestamp) desc, _loaded_at desc
) = 1
