-- The incremental fact must hold exactly what the sources hold right now: same row count
-- and same amounts per source and status. This is what catches a lookback window that is
-- too short, or a status update the incremental filter never re-read.
with expected as (
    select
        source_table,
        transaction_status,
        count(*) as row_count,
        sum(amount) as total_amount
    from {{ ref('int_transactions__unioned') }}
    group by 1, 2
),

actual as (
    select
        source_table,
        transaction_status,
        count(*) as row_count,
        sum(amount) as total_amount
    from {{ ref('fct_transaction') }}
    group by 1, 2
)

select
    coalesce(e.source_table, a.source_table) as source_table,
    coalesce(e.transaction_status, a.transaction_status) as transaction_status,
    e.row_count as expected_rows,
    a.row_count as actual_rows,
    e.total_amount as expected_amount,
    a.total_amount as actual_amount
from expected as e
full outer join actual as a
    on e.source_table = a.source_table
    and e.transaction_status = a.transaction_status
where
    e.row_count is distinct from a.row_count
    or e.total_amount is distinct from a.total_amount
