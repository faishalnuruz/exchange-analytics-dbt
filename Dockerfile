# Runs the whole demo with no local Python setup:  docker compose run --rm demo
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends make git \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home dbt \
    && mkdir /app && chown dbt:dbt /app

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=dbt:dbt . .
USER dbt

# The Makefile defaults to a local virtualenv; inside the image dbt is on PATH.
ENV PY=python DBT=dbt DBT_PROFILES_DIR=/app
# Bake dbt packages into the image so a run needs no network.
RUN dbt deps

CMD ["make", "demo"]
