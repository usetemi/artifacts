# Deploy

The host is one Phoenix release plus Postgres 14 or later. It speaks
plain HTTP; TLS belongs to whatever fronts it. Configuration is
environment variables:

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | 64+ random bytes, e.g. `openssl rand -base64 48` |
| `PHX_HOST` | the public host name, used to build artifact URLs and to check WebSocket origins |
| `PHX_SCHEME` | `https` (default) or `http` |
| `PHX_URL_PORT` | only when the public port is not 443 / 80 |
| `PORT` | the port the host listens on (default 4000) |

## Docker Compose

Also the local development database.

```sh
cd deploy
SECRET_KEY_BASE=$(openssl rand -base64 48) PHX_HOST=localhost PHX_SCHEME=http docker compose up -d
```

The app image builds from `../server/Dockerfile`, runs migrations on
boot, and listens on `localhost:4000`. Set `PHX_HOST`, `PHX_SCHEME`, and
`PORT` for a real host name behind your proxy. Data lives in the
`postgres` volume.

## Fly Sprites

A Sprite is a persistent Linux VM that sleeps when idle and wakes on the
next request, with a filesystem that survives sleep. `sprites/provision.sh`
turns a fresh Sprite into a host:

```sh
deploy/sprites/provision.sh artifacts ./artifacts-<version>-linux-x86_64.tar.gz
```

It installs Postgres from apt, unpacks the release (which bundles its own
Erlang runtime), registers two supervised services (`postgres`, then
`app` on the Sprite's HTTP port), makes the URL public, and takes a
checkpoint. The script prints the `https://<name>-<org>.sprites.app`
URL; that is `ARTIFACTS_URL` for every agent.

Behavior to expect:

- The Sprite pauses after idle time and drops open connections. Pages
  reconnect on their own and take a fresh state snapshot; the reconnect
  is what wakes the Sprite (100 to 500 ms warm, 1 to 2 s cold).
- Only one service can own the HTTP port, and it is the app.
- `--auth public` means anyone with a URL can reach it, which matches
  the no-auth model: artifact ids are the only secret.

To update: upload a new tarball with `sprite exec --file`, unpack it
over `/home/sprite/artifacts`, restart the `app` service, and take a
new checkpoint.
