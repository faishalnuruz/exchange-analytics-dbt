{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='event_id',
        on_schema_change='fail'
    )
}}

-- Grain: one row per product analytics event, after de-duplication in staging.
-- The largest table in the project, so it is incremental. Loaded by received_at, not
-- event_timestamp: an event from an offline device arrives days late with an old
-- event_timestamp, and filtering on event time would skip it forever.

with events as (
    select *
    from {{ ref('stg_tracking__events') }}
    where {{ incremental_lookback_filter('received_at') }}
)

select
    e.event_id,
    coalesce(u.user_key, {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }}) as user_key,
    cast(strftime(e.event_timestamp, '%Y%m%d') as integer) as date_key,
    e.user_id,
    e.anonymous_id,
    e.event_name,
    e.platform,
    e.event_timestamp,
    e.received_at,
    date_diff('second', e.event_timestamp, e.received_at) > 86400 as is_late_arrival
from events as e
left join {{ ref('dim_user') }} as u
    on e.user_id = u.user_id
    and e.event_timestamp >= u.valid_from
    and e.event_timestamp < u.valid_to
