select
    cast(price_date as date) as price_date,
    upper(asset_code) as asset_code,
    cast(price_usd as decimal(28, 8)) as price_usd
from {{ source('market', 'asset_prices') }}
qualify row_number() over (
    partition by price_date, upper(asset_code)
    order by _loaded_at desc
) = 1
