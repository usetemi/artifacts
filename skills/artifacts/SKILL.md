---
name: artifacts
description: Publish an interactive HTML page as an Artifact over MCP, keep it updated with new Versions, and wait for a Submission before continuing. Use when output is easier to see or interact with than to read as text (a dashboard, a board, options to compare, a form the agent needs answered), or when the user asks for an artifact, a page, a board, or a link. Requires an MCP connection to Artifacts, authenticated with a Harness or Agent key.
---

# Artifacts

One loop: publish a page, share its link, wait for a Submission, act on
it, publish the next Version. Every tool call is an Ash action, so it
runs under the same policies as the web app.

## When to publish a page instead of text

Publish a page when the person will iterate on the result, choose
between options, or add what they know, and hand it back rather than
answer in the thread.

- **Build in the knobs.** If a person is likely to ask for a different
  color, range, label, sort, or layout, put those controls on the page
  and let them turn the knobs themselves. Route through Submit only what
  needs new data or new code.
- **Ask on the page, not in the thread.** When you need something only a
  person knows, give them a place on the page to say it and read it back
  from State or the Submission, instead of leaving the question in the
  conversation.
- **Lay variants side by side** instead of describing two or three
  options in prose.
- **Expect more than one viewer.** State is shared and live: a person, a
  Harness, and an Agent can all be on the same page.
- **Read the History, not only the Submission.** What changed on the way
  to Submit is often the feedback.

The chrome's own Submit control has a note field, so a person can hand
the page back with just a word even when the page defines no Submit of
its own; that Submission's payload is `{"note": "..."}`.

## The MCP tools

Each tool is an `Artifact` or `Organization` action; call it with the
arguments its own schema lists. What follows is what each one does and
the arguments the domain model itself pins.

| Tool | Does |
| --- | --- |
| `list_organizations` | The Organizations you can act in. |
| `list_artifacts` | The open Artifacts in one Organization; pass `archived: true` to list archived ones instead. |
| `get_artifact` | One Artifact's metadata, and, with the tool's include-HTML argument, one Version's HTML. |
| `publish_artifact` | Create an Artifact (its first Version), or publish a new Version onto one that exists. Naming no Organization publishes to your Personal Organization (a Harness) or your own Organization (an Agent). |
| `get_state` | The Artifact's reduced State — the JSON object assembled from its rows. |
| `change_state` | Apply one batch of State ops together: `[{op: "set", path, value} \| {op: "delete", path}]`. Across calls, the last write to a path wins. |
| `submit` | Hand the page back, with an optional payload. |
| `wait` | Submissions made after a cursor; see below. |
| `history` | One page of the Artifact's History after a cursor: each Event, with the Version (HTML only when you ask for it), Submission, or ops it points at. |
| `rename_artifact` / `archive_artifact` / `unarchive_artifact` | Metadata and closeout. |

**`publish_artifact`'s `if_version`.** To publish a new Version onto an
existing Artifact, pass the Version you last saw as `if_version`. If
another Actor published first, the call is refused with `conflict`
instead of silently overwriting what they did — read the Artifact again,
fold your change onto its current Version, and retry with the new
`if_version`.

**`wait(artifact_id, since, timeout)`.** Returns the Submissions with id
greater than `since` — omit it to mean "after the latest Submission
now" — at once if any exist, otherwise it blocks until one arrives or
`timeout` elapses, then returns an empty list. `timeout` defaults to 45
seconds and is capped at 50, under both Claude Code's and Codex's
60-second default MCP tool timeout. Call `wait` again with the id of the
last Submission you saw as the next `since`, so nothing is missed and
nothing is read twice.

## The loop

1. Write the page against `window.artifact` (below).
2. `publish_artifact` with the HTML and no Artifact id to create it. Note
   the returned id and Version.
3. Share the web app link — `https://<app host>/a/<id>` — with whoever
   should look at it; the chrome, sign-in, and Submit live there, not on
   the content host that serves the raw page.
4. `wait` for a Submission.
5. On one, `get_state` (and `history`, if what changed on the way there
   matters) to see the page as the person left it, not only the payload.
6. Act, edit the HTML, and `publish_artifact` again with the Artifact id,
   the new HTML, and `if_version` set to the Version you last saw.
7. On `conflict`, re-read the Artifact and its State, fold your change
   onto what is current, and retry with the fresh `if_version`.
8. `wait` again with `since` set to the last Submission id, and repeat.

## The Page API

The host injects `window.artifact` before your scripts; no imports, no
build step. Its connection opens asynchronously, so await
`artifact.ready` before using it. Render from State, never from local
variables, so every viewer and every agent see the same thing.

```js
await artifact.ready;
artifact.id; artifact.version;
artifact.viewer;                       // {id, name}: the signed-in User

artifact.state.get("cards.c1");
await artifact.state.set("cards.c1.column", "done");
await artifact.state.delete("cards.c1");
const stop = artifact.state.subscribe((state) => render(state));

artifact.presence.track({cursor: [120, 44]});
artifact.presence.onChange((viewers) => renderPeers(viewers));
artifact.presence.list();              // [{id, name, ...meta}]

artifact.broadcast("pointer", {x, y});
artifact.on("pointer", (data, from) => flash(data, from));

await artifact.submit({choice: "B"});
await artifact.publish(html);          // rejects {code: "conflict"}
```

- `state.set` applies locally at once and resolves on commit; give list
  items their own paths (`items.<id>`) so concurrent edits do not clobber
  each other. `subscribe` fires once, synchronously, if already synced,
  then per change, coalesced per animation frame.
- `presence.track`/`onChange`/`list` share who has the page open; one
  entry per viewer, keyed by `id`, with whatever meta they tracked merged
  in. Presence and `broadcast` are ephemeral and never recorded.
- `submit` hands the page back to whoever is waiting; `publish`
  self-publishes a new Version of the page from inside itself.
- Every write rejects with one of the stable error codes below, or
  `unavailable`, which the runtime adds on its own for a write attempted
  while disconnected.

A compact complete example — a page that offers a choice, submits it,
and shows who else is looking:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Pick one</title>
  </head>
  <body>
    <div id="options"></div>
    <p id="peers"></p>
    <script type="module">
      await artifact.ready;

      function render(state) {
        document.getElementById("options").innerHTML = Object.entries(state.options ?? {})
          .map(([id, o]) => `<button data-id="${id}">${o.label}</button>`)
          .join("");
      }
      artifact.state.subscribe(render);

      document.getElementById("options").addEventListener("click", async (event) => {
        const id = event.target.dataset.id;
        if (!id) return;
        try {
          await artifact.state.set("choice", id);
          await artifact.submit({ choice: id });
        } catch (err) {
          if (err.code === "archived") alert("This page is archived.");
          else throw err;
        }
      });

      artifact.presence.track({});
      artifact.presence.onChange((viewers) => {
        const others = viewers.filter((v) => v.id !== artifact.viewer.id);
        document.getElementById("peers").textContent =
          others.length === 0 ? "" : `${others.length} other people are here.`;
      });
    </script>
  </body>
</html>
```

## Rules

- The page's CSP allows scripts from its own origin, cdnjs.cloudflare.com,
  cdn.jsdelivr.net, unpkg.com, and esm.sh; styles from those (except
  esm.sh) and fonts.googleapis.com; fonts from fonts.gstatic.com; images
  from anywhere. Every other connection is limited to the socket host.
  Inline what none of those cover.
- `wait` is the only way to wait; no polling loops.
- The Artifact's Organization is the only protection: any Actor in it can
  view the page, change its State, submit, and publish over it. Put
  nothing that Organization should not see into a page or its State.
- Nothing is deleted. `archive_artifact` closes an Artifact to further
  content changes; its Versions, State, Submissions, and History stay
  readable, and `unarchive_artifact` reopens it.

## Caps and error codes

Each Version is at most 16 MiB, each State value at most 256 KiB, and an
Artifact holds at most 10,000 State rows and 10,000 Submissions.

Every failure — from a tool call, the Page API, or the channel — resolves
to one of: `conflict` (a stale `if_version`), `archived` (the Artifact
refuses content changes), `not_found`, `forbidden`, `quota` (a cap
above), or `invalid`. The Page API adds `unavailable` on its own for a
write attempted while disconnected.
