-- Staging may drop versions and copies, never keys. Every key that exists in raw must
-- survive cleansing exactly once.
with checks as (
    select
        'users' as table_name,
        (select count(distinct user_id) from {{ source('app', 'users') }}) as raw_keys,
        (select count(*) from {{ ref('stg_app__users') }}) as staging_rows
    union all
    select
        'deposits',
        (select count(distinct deposit_id) from {{ source('app', 'deposits') }}),
        (select count(*) from {{ ref('stg_app__deposits') }})
    union all
    select
        'trades',
        (select count(distinct trade_id) from {{ source('app', 'trades') }}),
        (select count(*) from {{ ref('stg_app__trades') }})
    union all
    select
        'tracking_events',
        (select count(distinct event_id) from {{ source('tracking', 'tracking_events') }}),
        (select count(*) from {{ ref('stg_tracking__events') }})
)

select *
from checks
where raw_keys != staging_rows
