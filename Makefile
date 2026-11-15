PY  ?= .venv/bin/python
DBT ?= .venv/bin/dbt
export DBT_PROFILES_DIR := $(CURDIR)

DAY1 := 2026-10-24
DAY2 := 2026-10-31

.PHONY: setup day1 day2 double-load demo docs clean

setup:  ## create the virtualenv and install dbt + packages
	python3 -m venv .venv
	$(PY) -m pip install -q -r requirements.txt
	$(DBT) deps

day1:  ## first extract: full load into raw, first build, first snapshot
	$(PY) scripts/generate_data.py --as-of $(DAY1)
	$(PY) scripts/load_raw.py --as-of $(DAY1)
	$(DBT) build

day2:  ## a week later: new versions appended to raw -> SCD2 versions + incremental run
	$(PY) scripts/generate_data.py --as-of $(DAY2)
	$(PY) scripts/load_raw.py --as-of $(DAY2)
	$(DBT) build

double-load:  ## load day 2 again by mistake: raw grows, nothing downstream changes
	$(PY) scripts/load_raw.py --as-of $(DAY2)
	$(DBT) build

demo: clean day1 day2 double-load  ## the whole story from an empty warehouse

docs:  ## build the dbt docs site (target/static_index.html is a single shareable file)
	$(DBT) docs generate --static

clean:
	rm -rf exchange.duckdb exchange.duckdb.wal target data logs
