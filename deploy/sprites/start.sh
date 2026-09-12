#!/usr/bin/env bash
# The `app` service inside a Sprite: wait for Postgres, create the
# database once, migrate, then run the release in the foreground.
set -euo pipefail

set -a
# shellcheck disable=SC1091
. /home/sprite/artifacts.env
set +a

for _ in $(seq 1 30); do
    pg_isready -q -h localhost -U postgres && break
    sleep 1
done

psql -h localhost -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'artifacts'" | grep -q 1 \
    || createdb -h localhost -U postgres artifacts

/home/sprite/artifacts/bin/migrate
exec /home/sprite/artifacts/bin/server
