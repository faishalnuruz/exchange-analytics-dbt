{#- Use the configured schema name as-is (staging, core, reporting) instead of dbt's default
    <target_schema>_<custom_schema>. In a shared warehouse you would keep the prefix for
    developer targets so each person builds into their own schemas. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
