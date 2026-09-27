# Deploy

The host is one Elixir release plus Postgres 17. It serves two
hostnames — the web app and the page content — and needs a Google OAuth
client for sign-in. Configuration is environment variables:

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | `ecto://user:pass@host/db`. |
| `SECRET_KEY_BASE` | 64+ random bytes, e.g. `openssl rand -base64 48`. |
| `TOKEN_SIGNING_SECRET` | Signs AshAuthentication tokens; generate the same way. |
| `APP_HOST` | The web app's hostname: sign-in, `/auth`, `/api`, `/mcp`, and the chrome. |
| `CONTENT_HOST` | The page host's hostname: only the page route and the page socket, with no sign-in of its own. |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | From a Google OAuth Web client. |
| `GOOGLE_REDIRECT_URI` | Defaults to the app origin plus `/auth/user/google/callback`; whichever value is configured must match the Google Cloud Console client's registered redirect URI character for character. |
| `SIGNUP_EMAIL_DOMAINS` | The email domains allowed to sign up; empty means any. |
| `PORT` | The port the host listens on (default 4000). |
| `POOL_SIZE` | The Ecto connection pool size (default 10). |
| `DATABASE_SSL` | `true` to verify the database's certificate against the OS trust store (a hosted Postgres reached over TLS). Off by default. |
| `ECTO_IPV6` | `true` when the database is reachable only over IPv6 (Fly's private network). |
| `PHX_SCHEME` | `https` (default) or `http`. |
| `PHX_URL_PORT` | Only when the public port is neither 443 (`https`) nor the listening port (`http`). |

Nothing is ever deleted from the database: every Version, every State
change, and every Submission stays, and Archive only hides an Artifact.
Size the database, and its backups, for a record that only grows.

## Docker Compose

For local development, the test suite's database, and self-hosting on
one machine. Two hostnames are needed even locally; `localhost` and
`127.0.0.1` serve as the app and content hosts.

```sh
cd deploy
SECRET_KEY_BASE=$(openssl rand -base64 48) TOKEN_SIGNING_SECRET=$(openssl rand -base64 48) docker compose up -d
```

The app image is `ghcr.io/usetemi/artifacts`, runs migrations on boot,
and listens on `localhost:4000`. Set the `GOOGLE_CLIENT_ID` and
`GOOGLE_CLIENT_SECRET` environment variables to a real OAuth client for
sign-in to work. Data lives in the `postgres` volume; back that volume up
if the history matters to you.

`docker compose up -d postgres` alone gives `mix test` and `mix
phx.server` their database.

## Fly with Fly Managed Postgres

One Fly Machine that stops when idle and starts on the next request,
running the image `.github/workflows/release.yml` publishes to
`ghcr.io/usetemi/artifacts`, against a Fly Managed Postgres cluster in
the same region.

1. Create the app and the database cluster in the same region:

   ```sh
   fly apps create <app>
   fly mpg create --name <app>-db --region <region> --pg-major-version 17
   ```

2. Read the cluster's direct connection details and set `DATABASE_URL`
   from them. Use the direct host, not the pooled PgBouncer URL `fly mpg
   attach` would set: the Machine keeps its own Ecto pool (`POOL_SIZE`),
   so nothing should sit in front of it.

   ```sh
   fly mpg status <cluster-id> --json
   fly secrets set -a <app> DATABASE_URL='ecto://user:pass@<direct host>/<db>'
   ```

3. Generate and set the two signing secrets:

   ```sh
   fly secrets set -a <app> \
     SECRET_KEY_BASE="$(openssl rand -base64 48)" \
     TOKEN_SIGNING_SECRET="$(openssl rand -base64 48)"
   ```

4. In Google Cloud Console, create an OAuth client ID of type Web
   application. If every signer-in belongs to one Google Workspace, set
   the consent screen's User type to Internal so sign-in stays inside
   it; otherwise restrict who may sign up with `SIGNUP_EMAIL_DOMAINS`
   instead. Add `https://<APP_HOST>/auth/user/google/callback` as an
   authorized redirect URI, then set the credentials:

   ```sh
   fly secrets set -a <app> \
     GOOGLE_CLIENT_ID='...' \
     GOOGLE_CLIENT_SECRET='...'
   ```

5. Copy `fly/fly.toml`, replace `app`, `primary_region`, `image`,
   `APP_HOST`, and `CONTENT_HOST`, then allocate IPs and a certificate
   for each hostname:

   ```sh
   fly ips allocate-v4 -a <app>
   fly ips allocate-v6 -a <app>
   fly certs add <APP_HOST> -a <app>
   fly certs add <CONTENT_HOST> -a <app>
   ```

   Add the A and AAAA DNS records each `fly certs add` reports, at
   whatever registrar or DNS host you use for the two hostnames.

6. Deploy:

   ```sh
   fly deploy --config fly/fly.toml -a <app>
   ```

   The release command runs migrations before the new Machine takes
   traffic. To update later, bump the image tag in `fly.toml` and
   deploy again.

Behavior to expect:

- The Machine stops a few minutes after the last request and drops open
  connections. Pages reconnect on their own and take a fresh state
  snapshot; the reconnect is what starts the Machine.
- An open page's socket or a running `wait` holds a connection, so
  either keeps the Machine up. It stops only once nothing is connected.
- MPG's backups hold the record.
