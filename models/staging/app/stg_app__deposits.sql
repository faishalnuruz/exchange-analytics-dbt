select
    deposit_id,
    cast(user_id as bigint) as user_id,
    -- The backend writes currency codes in mixed case ('usdt', 'USDT'). Normalise once, here.
    upper(currency) as asset_code,
    cast(amount as decimal(28, 8)) as amount,
    cast(network_fee as decimal(28, 8)) as network_fee,
    status as deposit_status,
    cast(created_at as timestamp) as created_at,
    cast(completed_at as timestamp) as completed_at,
    cast(updated_at as timestamp) as updated_at
from {{ source('app', 'deposits') }}
