-- One row per user who has ever submitted KYC.

select
    user_id,
    count(*) as kyc_attempts,
    min(submitted_at) as first_kyc_submitted_at,
    min(case when kyc_status = 'approved' then reviewed_at end) as kyc_approved_at,
    arg_max(kyc_status, submitted_at) as latest_kyc_status
from {{ ref('stg_app__kyc_submissions') }}
group by user_id
