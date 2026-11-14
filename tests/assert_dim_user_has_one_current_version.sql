select
    user_id,
    count(*) as current_versions
from {{ ref('dim_user') }}
where is_current
group by user_id
having count(*) != 1
