#!/bin/sh
set -eu

readonly app_dir=/opt/cashflow

cd "$app_dir"
exec /usr/bin/docker compose --env-file .env --env-file .release.env -f compose.prod.yaml \
  exec -T postgres sh -ceu 'exec pg_dump \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --format=plain \
    --no-owner \
    --no-privileges'
