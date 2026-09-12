# Deploy

The host is one Phoenix release plus Postgres 14 or later. It speaks
plain HTTP; TLS belongs to whatever fronts it. Configuration is
environment variables:

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | `ecto://user:pass@host/db`. Drop any `?sslmode=...` suffix a provider appends and use `DATABASE_SSL` instead. |
| `DATABASE_SSL` | `true` when the database is reached over TLS (a hosted Postgres); the host then verifies the server's certificate against the OS trust store. Off by default. |
| `SECRET_KEY_BASE` | 64+ random bytes, e.g. `openssl rand -base64 48` |
| `PHX_HOST` | the public host name, used to build artifact URLs and to check WebSocket origins |
| `PHX_SCHEME` | `https` (default) or `http` |
| `PHX_URL_PORT` | only when the public port is neither 443 (https) nor the listening port (http) |
| `PORT` | the port the host listens on (default 4000) |

Nothing is ever deleted from the database: every version, every state
edit, and every submission stays, and `artifacts archive` only hides a
page. Size the database, and its backups, for a record that only grows.

## Docker Compose

For local development, the test suite's database, and self-hosting on
one machine.

```sh
cd deploy
SECRET_KEY_BASE=$(openssl rand -base64 48) PHX_HOST=localhost PHX_SCHEME=http docker compose up -d
```

The app image builds from `../server/Dockerfile`, runs migrations on
boot, and listens on `localhost:4000`. Set `PHX_HOST`, `PHX_SCHEME`, and
`PORT` for a real host name behind your proxy. Data lives in the
`postgres` volume; back that volume up if the history matters to you.

`docker compose up -d postgres` alone gives `mix test` and `mix
phx.server` their database.

## Fly Machines with Neon

One Fly Machine that stops when idle and starts on the next request,
running the container image each release publishes to
`ghcr.io/usetemi/artifacts`, against a Neon Postgres, which suspends
when idle, keeps its data in object storage, and has a free tier.
Neither side costs anything while nobody has a page open.

1. Create a Neon project and copy its **direct** connection string, not
   the pooled one: the host keeps its own connection pool, and Neon
   recommends the direct endpoint for that. Rewrite it as
   `ecto://user:pass@host/db`, without the `?sslmode=...` suffix.
2. Copy `fly/fly.toml`, set `app`, `PHX_HOST`, and `primary_region`,
   then:

   ```sh
   fly apps create <app>
   fly secrets set -a <app> DATABASE_URL='ecto://...' SECRET_KEY_BASE="$(openssl rand -base64 48)"
   fly deploy --config fly.toml
   ```

   The release command runs migrations before the new Machine takes
   traffic. `ARTIFACTS_URL` for every agent is `https://<app>.fly.dev`.
3. To update, bump the image tag in `fly.toml` and deploy again.

Behavior to expect:

- The Machine stops a few minutes after the last request and drops open
  connections. Pages reconnect on their own and take a fresh state
  snapshot; the reconnect is what starts the Machine. Neon resumes on
  the first query, which adds a moment to that first request.
- An open tab holds a WebSocket and a running `wait` holds a request, so
  either keeps the Machine, and with it the database, awake. Both
  suspend only when nothing is connected.
- The `fly.dev` URL is public. Artifact ids are the only secret, which
  matches the no-auth model.
