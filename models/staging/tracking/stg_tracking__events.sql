-- Two kinds of copies of an event_id end up in raw: clients resend an event when the first
-- request times out, and the loader's overlap re-reads recent rows. Keep the first copy
-- received. Every downstream count depends on this being done once, in one place.
select
    event_id,
    event_name,
    cast(event_timestamp as timestamp) as event_timestamp,
    cast(received_at as timestamp) as received_at,
    cast(user_id as bigint) as user_id,
    anonymous_id,
    platform
from {{ source('tracking', 'tracking_events') }}
qualify row_number() over (
    partition by event_id
    order by cast(received_at as timestamp), _loaded_at
) = 1
