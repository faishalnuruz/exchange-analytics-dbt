-- Deposits, withdrawals and trades reshaped to one common set of columns.
-- Each source keeps its own status vocabulary; they are mapped to one here.
-- arrived_at is when the source last wrote the row, and drives incremental loading downstream.

with deposits as (
    select
        'deposit' as source_table,
        deposit_id as source_id,
        user_id,
        'deposit' as transaction_type,
        asset_code,
        amount,
        network_fee as fee_amount,
        asset_code as fee_asset_code,
        deposit_status as transaction_status,
        created_at as occurred_at,
        updated_at as arrived_at
    from {{ ref('stg_app__deposits') }}
),

withdrawals as (
    select
        'withdrawal' as source_table,
        withdrawal_id as source_id,
        user_id,
        'withdrawal' as transaction_type,
        asset_code,
        amount,
        fee as fee_amount,
        asset_code as fee_asset_code,
        case withdrawal_status when 'rejected' then 'failed' else withdrawal_status end as transaction_status,
        created_at as occurred_at,
        updated_at as arrived_at
    from {{ ref('stg_app__withdrawals') }}
),

trades as (
    select
        'trade' as source_table,
        trade_id as source_id,
        user_id,
        'trade_' || side as transaction_type,
        base_asset_code as asset_code,
        quantity as amount,
        fee_quote as fee_amount,
        quote_asset_code as fee_asset_code,
        case trade_status when 'filled' then 'completed' else trade_status end as transaction_status,
        executed_at as occurred_at,
        updated_at as arrived_at
    from {{ ref('stg_app__trades') }}
)

select * from deposits
union all
select * from withdrawals
union all
select * from trades
