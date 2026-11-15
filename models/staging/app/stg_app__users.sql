-- Raw holds every version of a user. Keep the newest: latest updated_at, and for the same
-- version loaded more than once, the latest load.
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
qualify row_number() over (
    partition by user_id
    order by cast(updated_at as timestamp) desc, _loaded_at desc
) = 1
