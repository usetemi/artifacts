# server

The host: a Phoenix application backed by Postgres. See `../DESIGN.md`
for what it does and why.

```sh
docker compose -f ../deploy/docker-compose.yml up -d postgres   # or any Postgres 14+
mix setup
mix phx.server          # http://localhost:4000
mix test                # ExUnit
node --test assets/test # the browser runtime's state rules, on the shared fixture
```

`config/dev.exs` expects Postgres on `localhost:5432` as `postgres` /
`postgres`. The Compose file above publishes it there.
