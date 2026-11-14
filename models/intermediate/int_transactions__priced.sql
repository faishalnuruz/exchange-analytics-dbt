-- Adds USD values using the closing price of the day the transaction happened.
-- Inner logic is deliberately small so it can be unit tested (see _intermediate.yml).
-- A missing price leaves amount_usd NULL rather than 0: a NULL fails the not_null test and
-- gets noticed, a 0 quietly understates volume.

select
    t.source_table,
    t.source_id,
    t.user_id,
    t.transaction_type,
    t.asset_code,
    t.transaction_status,
    t.amount,
    cast(t.amount * p.price_usd as decimal(28, 8)) as amount_usd,
    cast(t.fee_amount * fp.price_usd as decimal(28, 8)) as fee_usd,
    t.occurred_at,
    t.arrived_at
from {{ ref('int_transactions__unioned') }} as t
left join {{ ref('stg_market__asset_prices') }} as p
    on t.asset_code = p.asset_code
    and cast(t.occurred_at as date) = p.price_date
left join {{ ref('stg_market__asset_prices') }} as fp
    on t.fee_asset_code = fp.asset_code
    and cast(t.occurred_at as date) = fp.price_date
