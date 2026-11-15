select
    trade_id,
    cast(user_id as bigint) as user_id,
    upper(base_asset) as base_asset_code,
    upper(quote_asset) as quote_asset_code,
    side,
    cast(quantity as decimal(28, 8)) as quantity,
    cast(price as decimal(28, 8)) as price,
    cast(fee_quote as decimal(28, 8)) as fee_quote,
    status as trade_status,
    cast(executed_at as timestamp) as executed_at,
    cast(updated_at as timestamp) as updated_at
from {{ source('app', 'trades') }}
qualify row_number() over (
    partition by trade_id
    order by cast(updated_at as timestamp) desc, _loaded_at desc
) = 1
