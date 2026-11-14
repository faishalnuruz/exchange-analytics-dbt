select
    withdrawal_id,
    cast(user_id as bigint) as user_id,
    upper(currency) as asset_code,
    cast(amount as decimal(28, 8)) as amount,
    cast(fee as decimal(28, 8)) as fee,
    status as withdrawal_status,
    cast(created_at as timestamp) as created_at,
    cast(completed_at as timestamp) as completed_at,
    cast(updated_at as timestamp) as updated_at
from {{ source('app', 'withdrawals') }}
