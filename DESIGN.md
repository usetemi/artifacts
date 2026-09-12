# Design

Artifacts lets a coding agent publish an interactive web page to a URL,
keep it updated in place, and receive what a person does on that page.
This document is the authoritative design: concepts, architecture, data
model, page API, CLI, and the limits of the first version. `README.md`
is the short user-facing summary.

## Problem

Terminal text is the wrong medium for a lot of what agents produce: a
dashboard, a triage board, a set of options to compare, a form that needs
a human's answers before the agent can continue. Hosted "artifacts" solve
this in proprietary harnesses, but they are tied to one vendor's account,
one harness, and one viewer. This project is the portable version:

- Any agent with a shell can publish and update a page.
- The page is live: a new version shows up in every open browser tab.
- The page can hold shared state that several viewers and the agent all
  read and write, with presence and ephemeral events, so pages can be
  collaborative rather than static.
- A viewer presses **Submit** when they are done, and the agent, which has
  been blocking on `wait`, receives the submission and continues.
- Everything that happened to a page is kept and can be read back: the
  agent's draft, each edit a person made, each submission, each
  republish. How people steer an agent's first draft is data worth
  having, so nothing is ever deleted.

The agent is deliberately not interrupted by every change. The viewer
decides when the agent should read the page.

## Scope of v1

In:

- Publish an HTML page; every publish is a new immutable version.
- Shared state per artifact, synced live to every viewer and the CLI.
- Presence and ephemeral broadcast between viewers of one artifact.
- Self-publish: a page can publish a new version of itself.
- Submit from the page or from the host chrome; `wait` in the CLI.
- An append-only record of every write, readable as a history; archive
  instead of delete.
- Two deploy targets: Docker Compose (local development, tests,
  self-hosting) and Fly Machines with a hosted Postgres.

Out (see [Limitations](#limitations) and [Later](#later)):

- Authentication, sharing controls, a gallery UI, comments, uploaded
  assets, multi-file artifacts, Markdown rendering, viewer names.

## Concepts

| Term | Meaning |
| --- | --- |
| **Artifact** | One page with a stable id and URL, a title, a sequence of versions, a state document, a submission log, and a history. |
| **Version** | One immutable published HTML document. The artifact's current version is what the URL serves. |
| **State** | The artifact's shared JSON document, stored as one row per path. Every viewer and the CLI read and write it; changes reach every subscriber live. |
| **Presence** | Who has the page open right now, with whatever each viewer chooses to share about themselves (a cursor, a selection). Ephemeral. |
| **Broadcast** | An ephemeral message from one viewer to the others on the same artifact. Not stored; may be missed by a viewer who was not connected. |
| **Submission** | A snapshot taken when a viewer presses Submit: the state at that moment, an optional page-supplied payload, the viewer id, and the version. Submissions are what `wait` returns. |
| **Event** | One entry in an artifact's append-only record: a version published, a state op applied, a submission made, or the archive. Every write appends one, attributed and timestamped. |
| **History** | An artifact's events in order, each joined with what it describes. Readable through the API and `artifacts history`. |
| **Archive** | The only kind of removal: the page disappears and refuses writes, every row stays, the history remains readable. |
| **Viewer** | A browser. Identified by a random id kept in that browser's local storage, so the same person on the same machine is one viewer across artifacts. Not an account, and there is no name. |
| **Agent** | Whatever runs the CLI: Claude Code, Codex, or a person at a shell. |
| **Host** | The server: it stores artifacts, serves pages inside a viewer chrome, syncs state, and answers the CLI. |

## Architecture

```
  agent (CLI)  ── HTTP/JSON ──►  host (Phoenix)  ◄── HTTP + WebSocket ──  browser
                                    │   └─ Channels + PubSub + Presence  ├─ chrome (LiveView)
                                 Postgres (beside it, or hosted)         └─ page iframe + runtime.js
```

One Elixir/Phoenix application is the host. Postgres runs beside it or
as a hosted service. Every artifact has one channel topic,
`artifact:<id>`. A page joins it and receives a snapshot of the state
rows; every later write is committed to Postgres and then broadcast on
the topic as row-level ops, which each connected page applies. The same
topic carries presence, broadcast, and version events. There is no
separate sync service and no message broker.

### Why this shape

- **Postgres rows plus Channels for state.** Shared state has to be
  durable, readable by the CLI, and live in every browser. Storing one
  row per path gives last-writer-wins per path (the same model Figma
  uses for object properties) and a trivial CLI (`state get` is a
  query). Fan-out is a PubSub broadcast after commit; a page that
  reconnects re-joins and takes a fresh snapshot, so a missed broadcast
  never leaves it stale. A CRDT was rejected: it adds a native
  dependency and a binary protocol the CLI would also have to speak, for
  conflict resolution that a submit-based loop does not need.
- **An append-only record beside the current view.** State rows
  overwrite each other, which is right for rendering and wrong for
  remembering. Every write therefore also appends an event in the same
  transaction, so the tables answer "what is the page now" and the
  events answer "how did it get here". The events point at version and
  submission rows rather than copying them; a state op is small and is
  stored inline.
- **Channels for the ephemeral parts.** Presence and broadcast are
  exactly what Phoenix.Presence and PubSub provide, and they need no
  persistence. Using the same channel for state keeps one connection
  per page and one reconnect path.
- **A sync engine is deferred, not ruled out.** Electric was the first
  choice for state sync and is recorded under rejected alternatives with
  the reason. Channels are the starting point; if they prove
  insufficient (resumable logs, offline pages, a client database), a
  sync engine can replace the fan-out without changing the rows.
- **Read on submit, not on change.** The agent blocks on `wait` and
  receives whole submissions. No push integration into any harness is
  required, so the same CLI and skill work in every harness. The viewer
  gets to finish their input before the agent reads it.
- **CLI as a static binary.** The host is Elixir, which is not something
  to install on every agent machine. A Rust binary with no runtime
  dependencies installs with one download, and the skill only has to
  teach one command.

### Trust boundary

The page is agent-authored HTML and runs in a sandboxed `<iframe>`
inside the chrome. In v1 the iframe is same-origin with the host, so a
page's script can call the host API for any artifact whose id it knows.
There are no cookies or tokens to steal because there is no
authentication. A separate content origin is the planned fix once
sharing controls exist (see [Later](#later)).

## Data model

```sql
artifacts (
  id              text primary key,   -- 22-char random, URL-safe; the only secret
  title           text not null,
  current_version integer not null default 0,
  archived_at     timestamptz,        -- set: hidden and closed to writes
  inserted_at     timestamptz not null,
  updated_at      timestamptz not null
)

versions (
  artifact_id     text references artifacts,
  number          integer not null,   -- 1, 2, 3 ...
  html            text not null,      -- exactly what was published, nothing injected
  published_by    text not null,      -- 'agent' or 'viewer:<viewer id>'
  inserted_at     timestamptz not null,
  primary key (artifact_id, number)
)

state_entries (
  artifact_id     text references artifacts,
  path            text not null,      -- dotted path, e.g. 'cards.c1.column'
  value           jsonb not null,
  updated_by      text not null,      -- 'agent' or 'viewer:<viewer id>'
  updated_at      timestamptz not null,
  primary key (artifact_id, path)
)

submissions (
  id              bigserial primary key,   -- monotonic; the wait cursor
  artifact_id     text references artifacts,
  version         integer not null,
  viewer_id       text,                    -- null when submitted by the agent
  state           jsonb not null,          -- reduced object at submit time
  payload         jsonb,                   -- from artifact.submit(payload)
  inserted_at     timestamptz not null
)

events (
  id              bigserial primary key,   -- the order of the history
  artifact_id     text references artifacts on delete restrict,
  kind            text not null,           -- version | state_op | submission | archive
  actor           text not null,           -- 'agent' or 'viewer:<viewer id>'
  data            jsonb not null,          -- {number} | the op | {id} | {}
  inserted_at     timestamptz not null
)
```

A page receives the artifact's `state_entries` as a snapshot when it
joins the channel and as ops afterwards. The other tables are read
through the HTTP API. The `events` reference restricts deletion of an
artifact row, so no path, including a manual one, can drop a history.

### State paths

State is a JSON object assembled from rows. Each row is one leaf at a
dotted `path`. `set("a.b", 1)` upserts the row `a.b`; `get()` builds
`{a: {b: 1}}`. Setting a path replaces any rows below it (`set("a",
{...})` deletes `a.*` and writes the leaves of the new object), so the
document never holds both `a` and `a.b`. `delete("a")` removes `a` and
`a.*`. Arrays are stored as one leaf value; to edit one element, store
elements at their own paths (`items.<id>`), which is also what makes
concurrent edits by different viewers land without clobbering each
other. `null` means absence: `set("a", null)` is `delete("a")`, and a
null inside an object writes no leaf, so no path ever reads back as
null. Last write wins per path; there are no transactions across paths.

Values are limited to 256 KiB serialized. An artifact holds at most
10,000 rows.

## Host

### Routes

| Route | Purpose |
| --- | --- |
| `GET /a/:id` | The chrome (LiveView): title, version, presence count, Submit button, and the page iframe. Reloads the iframe when a new version is published. `404` once archived. |
| `GET /a/:id/page` | The current version's HTML with the runtime `<script>` injected right after `<head>` (or first, when there is no head). Served with a CSP: scripts from this origin and the common CDNs, connections to this origin only, images from anywhere. Stored HTML is never modified. `404` once archived. |
| `GET /assets/js/runtime.js` | The page runtime (below), bundled with the Phoenix channel client so pages need no CDN. |
| `/socket` | Phoenix socket; channel `artifact:<id>` for the state snapshot and ops, presence, broadcast, submit, publish, and `version` events. |
| `POST /api/artifacts` | Create: `{title, html}` → `{id, url, version: 1}`. |
| `GET /api/artifacts` | List open artifacts: id, title, current version, updated at. |
| `GET /api/artifacts/:id` | Metadata, including `archived_at`. |
| `PUT /api/artifacts/:id` | Publish a new version: `{html, title?, if_version?}` → `{version}`; `409` when `if_version` is not current. |
| `POST /api/artifacts/:id/archive` | Archive: hide the page and close it to writes. Idempotent; returns the metadata. |
| `GET /api/artifacts/:id/history` | The history as NDJSON, oldest first, one event per line (see [History](#history)). |
| `GET /api/artifacts/:id/versions` | Version list without HTML. |
| `GET /api/artifacts/:id/versions/:n` | One version's HTML. |
| `GET /api/artifacts/:id/state` | Reduced state object. |
| `POST /api/artifacts/:id/state` | Apply ops: `[{op: "set", path, value} \| {op: "delete", path}]` in one transaction. |
| `POST /api/artifacts/:id/submissions` | Submit: `{payload?, viewer_id?}` → the submission row. |
| `GET /api/artifacts/:id/submissions?since=:cursor&timeout=:s` | List submissions after `cursor`; with `timeout`, long-poll until one arrives or the timeout passes (`204` on timeout). |

Every write attributes itself: `published_by`, `updated_by`, and an
event's `actor` are `agent` for CLI calls and `viewer:<id>` for page
calls. The page runtime sends its viewer id; the CLI sends nothing and
is trusted as the agent.

Once archived, every write (`PUT`, state ops, submissions, and the
channel's `state:ops`, `submit`, `publish`) answers `409 {"error":
"archived"}`; the reads keep working, since the record is the point.

### Channel protocol

A page joins `artifact:<id>` with `{viewer_id}`. The join reply
carries `{version, state}` where `state` is the flat map of rows, and
Phoenix.Presence sends the presence list right after. An archived
artifact refuses the join with `archived`; a page that was already open
learns of the archive from its next write.

| Direction | Event | Payload |
| --- | --- | --- |
| page → host | `state:ops` | `[{op: "set", path, value} \| {op: "delete", path}]`; reply `ok` after commit |
| host → pages | `state:ops` | the same ops plus `by`, sent to every subscriber after commit, the writer included |
| page → host | `presence:update` | meta object to merge into this viewer's presence |
| page → host | `broadcast` | `{topic, data}`; the host re-emits it to the other pages as `broadcast` with `from: {viewer: {id}}` |
| page → host | `submit` | `{payload}`; reply `{id}` |
| page → host | `publish` | `{html, if_version}`; reply `{version}` or `{error: "conflict"}` |
| host → pages | `version` | `{version, by}` on every publish, from the CLI or a page |

CLI writes take the HTTP routes and end in the same PubSub broadcast,
so a page cannot tell whether an op came from another viewer or from
the agent except by `by`.

### Publish and live reload

A publish inserts a version, bumps `current_version`, and broadcasts
`{version: n}` on `artifact:<id>`. The chrome reloads the iframe; state
survives because it lives in Postgres, not in the page. Self-publish from
the page sends `if_version` set to the version the page loaded, so two
viewers publishing at once produce one `409` instead of a silent
overwrite. The page runtime surfaces that as a `conflict` rejection; the
chrome is already reloading to the winner.

### Wait

`GET .../submissions?since=C&timeout=T` subscribes to PubSub for the
artifact, checks the table for rows with `id > C`, and either returns
them or blocks until a submission broadcast arrives or `T` seconds pass.
`T` is capped at 100 seconds so the request outlives no harness's
command timeout; the CLI loops when told to wait longer.

### History

`GET .../history` streams the artifact's events oldest first as NDJSON,
paging through the table so a long record never has to fit in memory
on either side. Each line is one event with the row it describes joined
in, so the output stands on its own:

```
{"id":1,"kind":"version","actor":"agent","at":"...","version":{"number":1,"published_by":"agent","html":"<!doctype html>..."}}
{"id":2,"kind":"state_op","actor":"viewer:v_8a1f","at":"...","op":{"op":"set","path":"cards.c1.column","value":"next"}}
{"id":3,"kind":"submission","actor":"viewer:v_8a1f","at":"...","submission":{"id":12,"version":1,"viewer_id":"v_8a1f","state":{...},"payload":null}}
{"id":4,"kind":"version","actor":"agent","at":"...","version":{"number":2,...}}
{"id":5,"kind":"archive","actor":"agent","at":"..."}
```

Ephemeral traffic (presence, broadcast) is not part of the history by
design: it never touches the database.

### Sleep and reconnect

On a host that stops when idle (a Fly Machine with auto-stop), open
connections drop. The channel client reconnects with backoff and
re-joins, and the join reply is a fresh snapshot, so nothing broadcast
during the gap is missed; the reconnect request is what starts the
host again. A submission that raced a stop is still in the table when
`wait` reconnects and re-reads from its cursor. An open tab's WebSocket
or a running `wait` keeps the host up, and with it a database that
suspends on idle; both stop only when nothing is connected.

## Page API

`runtime.js` defines `window.artifact`. It is available synchronously
because the host injects the script before the page's own scripts, but
its connections open asynchronously: read `artifact.ready` (a promise)
before relying on live data. Everything is plain JavaScript; no build
step is needed in a page.

```js
await artifact.ready;

artifact.id;           // "k7Qm3…"
artifact.version;      // 4
artifact.viewer.id;    // random id, stable per browser

// Shared state (durable, synced live to every viewer and the CLI)
artifact.state.get();                 // {} → current object
artifact.state.get("cards.c1");       // one subtree
await artifact.state.set("cards.c1.column", "done");
await artifact.state.set("cards.c2", {title: "Fix nav", column: "now"});
await artifact.state.delete("cards.c1");
const stop = artifact.state.subscribe((state) => render(state));

// Presence (ephemeral)
artifact.presence.track({cursor: [120, 44]}); // merges; call again to update
artifact.presence.list();                     // [{viewer: {id}, meta}]
artifact.presence.onChange((viewers) => renderPeers(viewers));

// Broadcast (ephemeral, not delivered to viewers who join later)
artifact.broadcast("pointer", {x, y});
artifact.on("pointer", (data, from) => flash(data, from.viewer));

// Hand the page back to the agent
await artifact.submit();                        // state snapshot
await artifact.submit({choice: "B", notes});    // plus a payload

// Replace this page with a new version (the chrome then reloads it)
await artifact.publish(html);   // rejects {code: "conflict"} if someone published first
```

Rules the runtime enforces or promises:

- `state.set` applies locally at once and resolves when the host has
  committed the row; the same op then arrives back on the channel and is
  a no-op. Other viewers' and the agent's writes arrive on the channel
  only. After a reconnect the runtime replaces its cache with the join
  snapshot and fires `subscribe` once.
- `subscribe` fires once with the current state after the initial sync,
  then on every change, coalesced per animation frame.
- `presence.track` may be called before `ready`; the meta is sent when
  the channel joins.
- The runtime never rewrites the DOM. Pages render themselves from
  state; the runtime only moves data.
- If the host is unreachable, calls reject with `{code: "unavailable"}`
  and the runtime keeps retrying the connections. A page should render
  from its last known state rather than fail. Once the artifact is
  archived, writes reject with `{code: "archived"}`.

The chrome's Submit button calls the same submit endpoint with no
payload, so a page that offers no Submit control of its own can still be
handed back.

## CLI

One static binary, `artifacts`, built with Rust and published as a
GitHub release for Linux and macOS on x86_64 and arm64. It talks only to
the HTTP API. The host URL comes from `ARTIFACTS_URL` or `--url`.

```
artifacts publish <file.html> --title "Deploy failures" [--id <id>] [--if-version n]
artifacts list
artifacts show <id>
artifacts versions <id>
artifacts get <id> [--version n] > page.html
artifacts state get <id> [path]
artifacts state set <id> <path> <json>
artifacts state delete <id> <path>
artifacts submit <id> [--payload <json>]
artifacts submissions <id> [--since <cursor>]
artifacts wait <id> [--since <cursor>] [--timeout <seconds>]
artifacts history <id> > record.ndjson
artifacts archive <id>
```

Output is JSON on stdout, one document per command, so an agent can read
it without parsing prose. `publish` prints `{id, url, version}`; `wait`
prints the submission (`{id, version, viewer_id, state, payload,
inserted_at}`); `history` streams the NDJSON described above; `get`
prints raw HTML.

`wait` semantics:

- Default timeout 90 seconds; the host caps a single request at 100.
  With `--timeout` larger than that, the CLI loops requests until the
  deadline. Agents should keep a single call under their harness's
  command timeout and re-run `wait` with `--since` on timeout.
- Exit code `0` with a submission; `3` on timeout with nothing to print;
  `1` on any error. The cursor to resume from is the submission `id` of
  the last one seen; `wait` without `--since` returns only submissions
  made after the call started.

## Skill

`skills/artifacts/SKILL.md` teaches an agent the loop and installs into
Claude Code and Codex with `npx skills add <owner>/<repo>`. It
covers: when a page beats text, how to write a page against
`window.artifact`, publish, then `wait`, then act on the submission,
then republish, and how to read the history. It also says what not to
do: no external assets that a CSP would block, no polling loops shorter
than a `wait`, no secrets in state (the id is the only protection).

## Repository layout

```
server/    Phoenix application (Elixir), including the runtime.js source and its build
cli/       Rust crate for the artifacts binary
skills/    artifacts/SKILL.md, installed into agents
examples/  complete pages to start from
deploy/    docker-compose.yml, fly/fly.toml, deploy docs
.github/   ci (tests) and release (CLI binaries, server release tarball, container image) workflows
DESIGN.md README.md LICENSE
```

## Deployment

The host needs Postgres 14 or later. Nothing else: no replication
settings, no object storage, no broker. Because nothing is deleted, the
database is where the record lives, and it should be one with backups.

**Docker Compose** (`deploy/docker-compose.yml`): the host image plus a
Postgres container, one named volume for the database, and a `.env`
with `SECRET_KEY_BASE` and the public host name. This is also the local
development and test database.

**Fly Machines with a hosted Postgres** (`deploy/fly/fly.toml`): one
Machine that stops when idle and starts on the next request, running the
container image the release workflow publishes, against a Postgres the
host does not run itself. Neon is the documented choice: it suspends
when idle, keeps its data in object storage, and has a free tier, so an
idle host costs nothing on either side. Migrations run as the release
command before each deploy.

Configuration is environment variables only: `DATABASE_URL`,
`DATABASE_SSL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`.

## Limitations

- **No authentication.** Anyone with an artifact's URL can view it,
  change its state, submit, and publish over it. The id is the only
  secret. Do not put private data in an artifact on a host reachable
  from the internet unless that is acceptable.
- **Same-origin pages.** A page's script can reach the host API for any
  artifact id it knows. Pages are trusted as much as the agent that
  wrote them.
- **A viewer is a browser.** The id lives in local storage: clearing it
  makes a new viewer, and the same person on two machines is two
  viewers. The history can tell viewers apart, not name them.
- **Nothing is deleted.** Archiving hides; the database only grows.
- **Single node.** One host process, one Postgres. PubSub fan-out is
  in-process; a second host node would need a shared PubSub adapter.
- **Connections drop when the host stops.** Clients reconnect; a viewer
  sees a short pause after idle time, not lost data.
- **Size caps.** 16 MiB per version, 256 KiB per state value, 10,000
  state rows and 10,000 submissions per artifact. The caps guard against
  a runaway page, and a refused write is visible; the history itself is
  uncapped.
- **No gallery.** `artifacts list` is the index; the host serves only
  artifact URLs so links stay unlisted.

## Rejected alternatives

- **Reusing an existing server.** The closest project publishes,
  versions, and comments on artifacts but has no shared state, no page
  runtime, and no self-publish, and is AGPL-licensed; a local plan-review
  tool has the blocking feedback loop but no hosting or persistence
  beyond one machine. Both informed this design (the blocking `wait`,
  the isolated content origin as a future step).
- **Push notifications into the agent.** Harness-specific, preview-only
  in one harness and absent in another, and it reads the page before the
  viewer is done. Submit plus `wait` is portable and intentional.
- **A CRDT for state.** Not needed for a submit-based loop; costs a
  native dependency and a second protocol in the CLI.
- **Electric as the state sync engine.** It was the first choice: rows
  synced to browsers as shapes over HTTP, resumable and cacheable, with a
  path to a client database. Two facts moved it to "later": the library
  that embeds Electric in a Phoenix app has had no release since October
  2025 and pins Electric to 1.1.10 while Electric is at 1.8, and running
  Electric as a separate service adds a third process plus a proxy route.
  Channels cover v1; the row model is unchanged if a sync engine returns.
- **SQLite.** Simpler to run than Postgres, but a later move to a sync
  engine or a second node would be a migration; Postgres costs one more
  process now and nothing later, and hosted Postgres with backups is
  what keeps the record safe.
- **Fly Sprites with Postgres inside.** The first hosting choice:
  sleep-on-idle compute with a filesystem that survives sleep, Postgres
  beside the app. Dropped once retention became a requirement: the data
  would live on one microVM's disk with no backups, and the Sprite's
  private network to a managed database was unverified. A Fly Machine
  with auto-stop is the same cost shape, and the database moves out.
- **Fly Managed Postgres.** Backups and a private network, but a fixed
  monthly price for a database that is idle most of the time. Neon's
  scale-to-zero matches the host's own idle behavior.
- **An object store for the record.** Streaming events to S3-compatible
  storage would put the dataset outside the database. One store with
  backups is simpler than two, and `history` exports the same data on
  demand.
- **Hard delete with an export first.** An archive that keeps the rows
  is one code path and one place to look; an export-then-delete leaves
  the only copy in a file.
- **Viewer display names.** A name a viewer types is neither identity
  nor authentication. The per-browser id already separates viewers in
  the history; names return with accounts, if ever.
- **A compatibility layer for another vendor's page API.** Pages written
  for a proprietary runtime would port, at the cost of matching a large
  and moving surface. This API is designed from the loop it serves.
- **An MCP server as the agent interface.** Typed tools, but per-harness
  configuration and a process per session. A CLI works everywhere a
  shell does and the skill carries the typing.

## Later

Candidates, in no order, each gated on a real need: viewer accounts and
sharing controls with a separate content origin; comments on the page
that ride into submissions; uploaded assets; multi-file artifacts;
Markdown pages; a page-side "ask the agent" call; a whole-host export.
