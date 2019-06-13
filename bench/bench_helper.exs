# Micro benchmarks
Code.require_file("scripts/micro/load_bench.exs", __DIR__)
Code.require_file("scripts/micro/to_sql_bench.exs", __DIR__)

## Macro benchmarks needs postgresql and mysql up and running
Code.require_file("scripts/macro/insert_bench.exs", __DIR__)
Code.require_file("scripts/macro/all_bench.exs", __DIR__)
