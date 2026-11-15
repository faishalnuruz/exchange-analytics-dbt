PY  ?= .venv/bin/python
DBT ?= .venv/bin/dbt
export DBT_PROFILES_DIR := $(CURDIR)

.PHONY: setup day1 day2 demo docs clean

setup:  ## create the virtualenv and install dbt + packages
	python3 -m venv .venv
	$(PY) -m pip install -q -r requirements.txt
	$(DBT) deps

day1:  ## first extract and first build (full load, first snapshot)
	$(PY) scripts/generate_data.py --as-of 2026-10-24
	$(DBT) build

day2:  ## a week later: new and changed rows -> SCD2 versions + incremental run
	$(PY) scripts/generate_data.py --as-of 2026-10-31
	$(DBT) build

demo: clean day1 day2  ## the whole story from an empty warehouse

docs:  ## build the dbt docs site (target/static_index.html is a single shareable file)
	$(DBT) docs generate --static

clean:
	rm -rf exchange.duckdb exchange.duckdb.wal target data logs
