select
    cast(user_id as bigint) as user_id,
    -- PII stops here. Downstream models only ever see the hash.
    md5(lower(trim(email))) as email_hash,
    upper(country_code) as country_code,
    signup_channel,
    cast(kyc_level as integer) as kyc_level,
    account_status,
    cast(created_at as timestamp) as created_at,
    cast(updated_at as timestamp) as updated_at
from {{ source('app', 'users') }}
