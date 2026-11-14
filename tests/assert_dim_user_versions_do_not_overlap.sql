-- A point-in-time join must match exactly one version. Two versions of the same user
-- overlapping in time would silently duplicate fact rows.
select
    a.user_id,
    a.user_key as version_a,
    b.user_key as version_b
from {{ ref('dim_user') }} as a
inner join {{ ref('dim_user') }} as b
    on a.user_id = b.user_id
    and a.user_key != b.user_key
    and a.valid_from < b.valid_to
    and b.valid_from < a.valid_to
