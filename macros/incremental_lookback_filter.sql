{#- Predicate for incremental models: keep rows the warehouse received at or after
    (this table's high-water mark - lookback).

    The column must be an ARRIVAL time (updated_at, received_at), not the business event time.
    A trade executed last week but written today has a fresh updated_at, so it is picked up
    however late it is. The lookback only has to cover extraction jitter around the watermark.

    The watermark comes from the target table, not current_date, so a rerun after a three-day
    outage simply continues from where the table stopped. -#}
{% macro incremental_lookback_filter(column) -%}
    {%- if is_incremental() -%}
        {{ column }} >= (
            select coalesce(max({{ column }}), timestamp '1900-01-01')
                - interval '{{ var("incremental_lookback_days") }} days'
            from {{ this }}
        )
    {%- else -%}
        true
    {%- endif -%}
{%- endmacro %}
