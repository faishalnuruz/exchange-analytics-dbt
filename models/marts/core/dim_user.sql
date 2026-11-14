-- Type 2 user dimension. One row per user per version.
--
-- Facts join on user_id AND the event time falling inside [valid_from, valid_to), so a trade
-- made while the user was KYC level 0 in Indonesia stays attributed that way after they
-- upgrade or move.
--
-- Two adjustments to the raw snapshot:
--   1. A user's first version starts at registration, not at the first snapshot run.
--      Otherwise every fact older than the first snapshot would find no matching version.
--   2. A fixed 'unknown' member (user_id -1) exists so facts with no user, such as anonymous
--      tracking events, still carry a valid foreign key instead of NULL.

with versions as (
    select
        *,
        row_number() over (partition by user_id order by dbt_valid_from) as version_number
    from {{ ref('snap_app__users') }}
),

users as (
    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'dbt_valid_from']) }} as user_key,
        user_id,
        email_hash,
        country_code,
        signup_channel,
        kyc_level,
        account_status,
        created_at as registered_at,
        case when version_number = 1 then created_at else dbt_valid_from end as valid_from,
        dbt_valid_to as valid_to,
        dbt_valid_to = timestamp '9999-12-31' as is_current
    from versions
),

unknown_member as (
    select
        {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }} as user_key,
        cast(-1 as bigint) as user_id,
        cast(null as varchar) as email_hash,
        'ZZ' as country_code,
        'unknown' as signup_channel,
        cast(0 as integer) as kyc_level,
        'unknown' as account_status,
        cast(null as timestamp) as registered_at,
        timestamp '1900-01-01' as valid_from,
        timestamp '9999-12-31' as valid_to,
        true as is_current
)

select * from users
union all
select * from unknown_member
