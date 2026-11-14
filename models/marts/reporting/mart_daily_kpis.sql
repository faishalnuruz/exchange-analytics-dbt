-- Grain: one row per calendar day, including days with no activity (the date dimension is
-- the spine, so a quiet day shows as 0 instead of going missing from the chart).

with registrations as (
    select cast(registered_at as date) as date_day, count(*) as new_registrations
    from {{ ref('mart_user_funnel') }}
    group by 1
),

kyc_approvals as (
    select cast(kyc_approved_at as date) as date_day, count(*) as kyc_approvals
    from {{ ref('mart_user_funnel') }}
    where kyc_approved_at is not null
    group by 1
),

transactions as (
    select
        cast(occurred_at as date) as date_day,
        count(distinct case when transaction_type = 'deposit' then user_id end) as depositing_users,
        count(distinct case when transaction_type like 'trade_%' then user_id end) as trading_users,
        coalesce(sum(case when transaction_type = 'deposit' then amount_usd end), 0) as deposit_volume_usd,
        coalesce(sum(case when transaction_type = 'withdrawal' then amount_usd end), 0) as withdrawal_volume_usd,
        coalesce(sum(case when transaction_type like 'trade_%' then amount_usd end), 0) as trade_volume_usd,
        coalesce(sum(case when transaction_type in ('trade_buy', 'trade_sell', 'withdrawal') then fee_usd end), 0)
            as fee_revenue_usd
    from {{ ref('fct_transaction') }}
    where transaction_status = 'completed'
    group by 1
),

events as (
    select cast(event_timestamp as date) as date_day, count(distinct user_id) as daily_active_users
    from {{ ref('fct_event') }}
    where user_id is not null
    group by 1
)

select
    d.date_day,
    coalesce(r.new_registrations, 0) as new_registrations,
    coalesce(k.kyc_approvals, 0) as kyc_approvals,
    coalesce(e.daily_active_users, 0) as daily_active_users,
    coalesce(t.depositing_users, 0) as depositing_users,
    coalesce(t.trading_users, 0) as trading_users,
    coalesce(t.deposit_volume_usd, 0) as deposit_volume_usd,
    coalesce(t.withdrawal_volume_usd, 0) as withdrawal_volume_usd,
    coalesce(t.deposit_volume_usd, 0) - coalesce(t.withdrawal_volume_usd, 0) as net_flow_usd,
    coalesce(t.trade_volume_usd, 0) as trade_volume_usd,
    coalesce(t.fee_revenue_usd, 0) as fee_revenue_usd
from {{ ref('dim_date') }} as d
left join registrations as r on d.date_day = r.date_day
left join kyc_approvals as k on d.date_day = k.date_day
left join transactions as t on d.date_day = t.date_day
left join events as e on d.date_day = e.date_day
where d.date_day <= (select cast(max(received_at) as date) from {{ ref('fct_event') }})
