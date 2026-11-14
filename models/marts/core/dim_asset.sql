select
    {{ dbt_utils.generate_surrogate_key(['asset_code']) }} as asset_key,
    asset_code,
    asset_name,
    asset_type,
    asset_type in ('stablecoin', 'fiat') as is_usd_pegged
from {{ ref('asset_reference') }}
