# Artifacts

Interactive pages published by coding agents. An agent publishes an
HTML page to a URL, keeps it updated in place, and blocks until a person
presses **Submit** on that page. Works with Claude Code, Codex, and any
agent that can run a command.

```
$ artifacts publish triage.html --title "Issue triage"
{"id":"k7Qm3xVb2pLw9RtY","url":"https://artifacts.example/a/k7Qm3xVb2pLw9RtY","version":1}

$ artifacts wait k7Qm3xVb2pLw9RtY
{"id":12,"version":1,"viewer_id":"v_8a1f","state":{"cards":{"c1":{"column":"now"}}},"payload":null,...}
```

## Why

Some agent output is better seen than read: a dashboard, a set of
options to compare, a board to drag things around, a form that needs
answers before the agent can continue. Hosted artifacts exist inside
proprietary harnesses, tied to one vendor, one account, and one viewer.
This is the self-hosted, harness-neutral version.

## What a page gets

Every page is served with `window.artifact`:

- **Shared state**: a JSON document synced live to every viewer and to
  the agent's CLI. `artifact.state.set("cards.c1.column", "done")`.
- **Presence**: who has the page open, with whatever they share about
  themselves. `artifact.presence.track({name: "Ana"})`.
- **Broadcast**: ephemeral events between viewers. `artifact.broadcast("pointer", {x, y})`.
- **Submit**: `artifact.submit(payload)` hands the page back to the
  waiting agent. The host chrome also has a Submit button, so every
  page can be submitted.
- **Self-publish**: `artifact.publish(html)` replaces the page with a
  new version; every open tab reloads.

Publishing a new version from the agent updates every open tab in place.

## Install

Server: see `deploy/` for Docker Compose (also local development) and
Fly Sprites. The server is a Phoenix application with Postgres and an
embedded [Electric](https://github.com/electric-sql/electric) sync
engine; Postgres needs `wal_level=logical`.

CLI: download the `artifacts` binary for your platform from the
releases page and set `ARTIFACTS_URL` to your server.

Agent skill: install `skill/` into Claude Code or Codex so the agent
knows the loop: write a page against `window.artifact`, `publish`,
`wait`, act on the submission, republish.

## Limitations

There is no authentication in this version. Anyone with an artifact's
URL can view it, change its state, submit, and publish over it. The id
is the only secret, and there is no gallery page, so links stay
unlisted. Pages run same-origin with the host. One host process, one
Postgres. Full list and rationale in [DESIGN.md](DESIGN.md).

## License

MIT.
