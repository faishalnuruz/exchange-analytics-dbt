with days as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('dim_date_start') ~ "' as date)",
        end_date="cast('" ~ var('dim_date_end') ~ "' as date)"
    ) }}
)

select
    cast(strftime(date_day, '%Y%m%d') as integer) as date_key,
    cast(date_day as date) as date_day,
    year(date_day) as year_number,
    quarter(date_day) as quarter_number,
    month(date_day) as month_number,
    strftime(date_day, '%B') as month_name,
    cast(date_trunc('month', date_day) as date) as month_start_date,
    cast(date_trunc('week', date_day) as date) as week_start_date,
    isodow(date_day) as day_of_week,
    strftime(date_day, '%A') as day_name,
    isodow(date_day) in (6, 7) as is_weekend
from days
