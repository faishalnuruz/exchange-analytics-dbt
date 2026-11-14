-- Grain: one row per KYC attempt. Small table, rebuilt in full each run: pending rows change
-- when reviewed, and a full rebuild is simpler than incremental logic at this size.

select
    {{ dbt_utils.generate_surrogate_key(['k.submission_id']) }} as kyc_submission_key,
    coalesce(u.user_key, {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }}) as user_key,
    cast(strftime(k.submitted_at, '%Y%m%d') as integer) as submitted_date_key,
    k.submission_id,
    k.user_id,
    k.attempt_number,
    k.document_type,
    k.kyc_status,
    k.rejection_reason,
    k.submitted_at,
    k.reviewed_at,
    date_diff('minute', k.submitted_at, k.reviewed_at) / 60.0 as review_hours
from {{ ref('stg_app__kyc_submissions') }} as k
left join {{ ref('dim_user') }} as u
    on k.user_id = u.user_id
    and k.submitted_at >= u.valid_from
    and k.submitted_at < u.valid_to
