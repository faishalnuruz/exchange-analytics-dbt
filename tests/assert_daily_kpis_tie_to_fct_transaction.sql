-- Two grains of the same numbers must agree: the daily mart summed over all days equals
-- completed volume in the fact.
with mart as (
    select
        sum(deposit_volume_usd) as deposit_usd,
        sum(trade_volume_usd) as trade_usd
    from {{ ref('mart_daily_kpis') }}
),

fact as (
    select
        coalesce(sum(case when transaction_type = 'deposit' then amount_usd end), 0) as deposit_usd,
        coalesce(sum(case when transaction_type like 'trade_%' then amount_usd end), 0) as trade_usd
    from {{ ref('fct_transaction') }}
    where transaction_status = 'completed'
)

select *
from mart
cross join fact
where
    abs(mart.deposit_usd - fact.deposit_usd) > 0.01
    or abs(mart.trade_usd - fact.trade_usd) > 0.01
