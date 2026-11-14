-- Grain: one row per user. Registration -> KYC -> first deposit -> first trade, with the
-- user's CURRENT attributes (is_current), because funnel reports segment by who the user is now.

with first_transactions as (
    select
        user_id,
        min(case when transaction_type = 'deposit' then occurred_at end) as first_deposit_at,
        min(case when transaction_type like 'trade_%' then occurred_at end) as first_trade_at,
        min(case when transaction_type = 'withdrawal' then occurred_at end) as first_withdrawal_at
    from {{ ref('fct_transaction') }}
    where transaction_status = 'completed'
    group by user_id
)

select
    u.user_id,
    u.country_code,
    u.signup_channel,
    u.account_status,
    u.registered_at,
    k.first_kyc_submitted_at,
    k.kyc_approved_at,
    coalesce(k.kyc_attempts, 0) as kyc_attempts,
    t.first_deposit_at,
    t.first_trade_at,
    t.first_withdrawal_at,
    k.first_kyc_submitted_at is not null as has_submitted_kyc,
    k.kyc_approved_at is not null as is_kyc_approved,
    t.first_deposit_at is not null as has_deposited,
    t.first_trade_at is not null as has_traded,
    date_diff('hour', u.registered_at, k.kyc_approved_at) as hours_registration_to_kyc_approved,
    date_diff('hour', k.kyc_approved_at, t.first_deposit_at) as hours_kyc_approved_to_first_deposit
from {{ ref('dim_user') }} as u
left join {{ ref('int_users__kyc_summary') }} as k
    on u.user_id = k.user_id
left join first_transactions as t
    on u.user_id = t.user_id
where
    u.is_current
    and u.user_id != -1
