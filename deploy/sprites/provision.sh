#!/usr/bin/env bash
# Provision a Fly Sprite that runs the artifacts host and its Postgres.
#
# The host ships as a self-contained mix release (it bundles the Erlang
# runtime), so the Sprite needs only Postgres from apt. Two supervised
# services run inside: `postgres`, then `app` on the Sprite's HTTP port.
# The last step takes a checkpoint, which is the Sprite's image from
# then on.
#
# Usage: deploy/sprites/provision.sh <sprite-name> <release-tarball>
#   <release-tarball> is the artifacts-*-linux-x86_64.tar.gz from a
#   GitHub release, or the output of `mix release` on Debian x86_64.
#
# Requires the `sprite` CLI, signed in (https://docs.sprites.dev/cli/).
set -euo pipefail

name=${1:?sprite name}
tarball=${2:?release tarball}
here=$(cd "$(dirname "$0")" && pwd)

sprite create --skip-console "$name"

sprite exec -s "$name" --file "$tarball:/home/sprite/release.tar.gz" \
    --file "$here/start.sh:/home/sprite/start.sh" -- bash -s <<'EOF'
set -euo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql
sudo systemctl disable --now postgresql 2>/dev/null || true

pg_bin=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)
mkdir -p /home/sprite/pgdata
if [ ! -f /home/sprite/pgdata/PG_VERSION ]; then
    "$pg_bin/initdb" -D /home/sprite/pgdata --auth=trust -U postgres >/dev/null
fi

mkdir -p /home/sprite/artifacts
tar -xzf /home/sprite/release.tar.gz -C /home/sprite/artifacts
chmod +x /home/sprite/start.sh

secret=$(head -c 48 /dev/urandom | base64 | tr -d '\n')
cat >/home/sprite/artifacts.env <<ENV
DATABASE_URL=ecto://postgres@localhost/artifacts
SECRET_KEY_BASE=$secret
PHX_HOST=$(sprite-env url 2>/dev/null | sed -E 's#https?://##; s#/$##' || echo localhost)
PORT=4000
ENV

sprite-env services create postgres \
    --cmd "$pg_bin/postgres" --args "-D,/home/sprite/pgdata"
sprite-env services create app \
    --cmd /home/sprite/start.sh --dir /home/sprite --needs postgres --http-port 4000
EOF

sprite url update -s "$name" --auth public
sprite checkpoint create -s "$name" --comment "artifacts host provisioned"
sprite url -s "$name"
