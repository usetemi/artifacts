# Artifacts

A persistent, provider-agnostic host for live HTML pages that people and
coding agents build together. An agent in any harness writes a page for
the problem in front of it — a board, a form, a dashboard, a spec — and
publishes it to an Organization. People and other agents open it, change
it, and hand it back. Every Version, every State change, and every
Submission is recorded and kept, so how people and agents shape each
other's work can be studied later.

`DOMAIN.md` is the ubiquitous language and the domain rules. `DESIGN.md`
is how each rule is built: architecture, the Ash resources, the page
runtime, and the MCP and HTTP interfaces.

## Parts

- **Web app** — Google sign-in, an Organization's open Artifacts, the
  page chrome (title, Version, Presence, Submit), and settings — served
  from the app host.
- **Page host** — the published HTML plus the runtime script
  (`window.artifact`), giving a page shared State, Presence, Broadcast,
  Submit, and Self-Publish — served from a separate content host that
  holds no sign-in.
- **MCP and HTTP API** — the same actions for a coding agent: publish a
  Version, read and change State, submit, wait for a Submission, read
  the History.

## Signing in

A person signs in with Google. An Instance may restrict sign-up to a set
of allowed email domains (`SIGNUP_EMAIL_DOMAINS`); sign-up creates the
User's Personal Organization in the same step.

## Connecting an agent

A Harness — a person's coding tool, such as Claude Code or Codex —
authenticates with a key that person issued, prefixed `arth_`, and acts
with that person's rights. An Agent — a coworker such as Pidgey —
authenticates with its own key, prefixed `arta_`, and acts as itself in
its Organization. Both connect the same way, over MCP:

```
claude mcp add --transport http artifacts https://usetemi.art/mcp \
  --header "Authorization: Bearer arth_…"
```

`skills/artifacts/SKILL.md` teaches the loop: publish a page, wait for a
Submission, act on it, publish the next Version.

## Local development

```sh
cd deploy
SECRET_KEY_BASE=$(openssl rand -base64 48) TOKEN_SIGNING_SECRET=$(openssl rand -base64 48) docker compose up -d
```

or, against a local Postgres 17, from `server/`:

```sh
mix setup
mix phx.server
```

See [`deploy/README.md`](deploy/README.md) for the full environment
variable list and the Fly deployment.

## Limitations

- **Content origin is shared across artifacts.** Every page runs on one
  content origin, so pages share its localStorage and can read what
  another page stored there.
- **A page can exfiltrate what its viewer can see of its own artifact.**
  The CSP limits connections but allows images from anywhere.
- **Single node.** PubSub fan-out is in-process; a second node needs a
  shared PubSub adapter.
- **Nothing is deleted.** The database only grows.

Full rationale in [`DESIGN.md`](DESIGN.md).

## License

MIT.
