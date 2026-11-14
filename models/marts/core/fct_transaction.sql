{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='transaction_key',
        on_schema_change='fail'
    )
}}

-- Grain: one row per money movement (one deposit, one withdrawal, or one trade execution).
--
-- Incremental, delete+insert on the key:
--   * rows are selected by arrived_at (when the source wrote them), so a late trade or a
--     deposit that flips pending -> completed is re-read and REPLACES its earlier version
--   * running it twice produces the same table, because a re-read row deletes itself first
--
-- user_key is the dim_user version that was valid when the transaction happened.

with transactions as (
    select *
    from {{ ref('int_transactions__priced') }}
    where {{ incremental_lookback_filter('arrived_at') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['t.source_table', 't.source_id']) }} as transaction_key,
    coalesce(u.user_key, {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }}) as user_key,
    a.asset_key,
    cast(strftime(t.occurred_at, '%Y%m%d') as integer) as date_key,
    -- Degenerate dimensions: identifiers with no attributes of their own.
    t.source_table,
    t.source_id,
    t.user_id,
    t.transaction_type,
    t.transaction_status,
    t.amount,
    t.amount_usd,
    t.fee_usd,
    t.occurred_at,
    t.arrived_at
from transactions as t
left join {{ ref('dim_user') }} as u
    on t.user_id = u.user_id
    and t.occurred_at >= u.valid_from
    and t.occurred_at < u.valid_to
left join {{ ref('dim_asset') }} as a
    on t.asset_code = a.asset_code
