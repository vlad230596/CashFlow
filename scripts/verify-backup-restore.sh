#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 DUMP_PATH" >&2
  exit 64
fi

readonly dump_path=$1
readonly container=cashflow-restore-verify

cleanup() {
  /usr/bin/docker rm -f "$container" >/dev/null 2>&1 || true
  rm -f -- "$dump_path"
}
trap cleanup EXIT HUP INT TERM

test -s "$dump_path"
if /usr/bin/docker ps -a --format '{{.Names}}' | grep -Fx "$container" >/dev/null; then
  echo "container already exists: $container" >&2
  exit 65
fi

/usr/bin/docker run \
  --detach \
  --rm \
  --name "$container" \
  --network none \
  --memory 384m \
  --cpus 1 \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:17.6-alpine >/dev/null

attempt=0
until /usr/bin/docker exec "$container" pg_isready -U postgres -d postgres >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo 'temporary PostgreSQL did not become ready' >&2
    exit 1
  fi
  sleep 1
done

/usr/bin/docker exec "$container" createdb -U postgres restorecheck
/usr/bin/docker exec -i "$container" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d restorecheck \
  <"$dump_path" >/dev/null

table_count=$(/usr/bin/docker exec "$container" \
  psql -X -A -t -U postgres -d restorecheck \
  -c "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'")
revision=$(/usr/bin/docker exec "$container" \
  psql -X -A -t -U postgres -d restorecheck \
  -c 'select version_num from alembic_version')

if [ "$table_count" -ne 8 ]; then
  echo "unexpected restored public table count: $table_count" >&2
  exit 1
fi
if [ "$revision" != '0002_authentication' ]; then
  echo "unexpected restored Alembic revision: $revision" >&2
  exit 1
fi

echo "restore verified: public tables=$table_count, alembic=$revision"
