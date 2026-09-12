---
name: artifacts
description: Publish an interactive HTML page to a URL with the `artifacts` CLI, keep it updated in place, and block until a person presses Submit on it. Use when output is easier to see or interact with than to read as text (a dashboard, a board, options to compare, a form the agent needs answered), or when the user asks for an artifact, a page, a board, or a link. Requires ARTIFACTS_URL.
---

# Artifacts

One loop: write a page, publish it, wait for the viewer to submit, act on
the submission, republish. Every command prints one JSON document.

## The loop

```sh
artifacts publish page.html --title "Issue triage"     # {"id": "...", "url": "...", "version": 1}
artifacts wait <id>                                    # blocks; prints the submission
artifacts publish page.html --id <id>                  # new version, every open tab reloads
```

Tell the user the `url` as soon as `publish` returns. Then run `wait`.
It exits `0` with the submission, `3` when nothing arrived within
`--timeout` (default 90 s; keep one call under your command timeout and
re-run `wait --since <last id>` to keep waiting), `1` on error.

A submission is `{id, version, viewer_id, state, payload, inserted_at}`:
`state` is the page's shared state at the moment of Submit, `payload` is
whatever the page passed to `artifact.submit(payload)` (null from the
chrome's Submit button).

Everything that happens to a page is kept. `artifacts history <id>`
prints it in order, one JSON line per event: each version, each state
edit with the viewer who made it, each submission. Read it to see how
the viewer changed your draft, not only what they submitted.

## Writing a page

Publish one self-contained HTML file. The host injects `window.artifact`
before your scripts; no imports, no build step. Render from state,
never from local variables, so every viewer and the agent see the same
thing:

```html
<script>
  artifact.state.subscribe((state) => render(state));
  button.onclick = () => artifact.state.set("cards.c1.column", "done");
</script>
```

- `artifact.state.get(path?)`, `set(path, value)`, `delete(path)`,
  `subscribe(fn)`. Paths are dotted; give list items their own paths
  (`items.<id>`) so concurrent edits do not clobber each other; `null`
  deletes.
- `artifact.viewer.id` is this browser's random id. There are no names
  or accounts.
- `artifact.presence.track(meta)`, `list()`, `onChange(fn)` for who is
  viewing.
- `artifact.broadcast(topic, data)`, `artifact.on(topic, fn)` for
  ephemeral moments.
- `artifact.submit(payload?)` when the page has its own Submit; the
  chrome always shows one too.
- `artifact.publish(html)` replaces the page from inside the page.

Seed initial data from the CLI rather than hardcoding it in the page:

```sh
artifacts state set <id> cards '{"c1": {"title": "Fix nav", "column": "now"}}'
artifacts state get <id> cards.c1
```

## Rules

- Scripts and fonts may come from cdnjs, jsDelivr, unpkg, esm.sh, and
  Google Fonts; every other request must stay on the host. Inline
  everything else.
- No polling loops. `wait` is the only way to wait.
- The artifact id is the only protection: anyone with the URL can view,
  edit state, and submit. Put nothing secret in a page or its state.
- `publish --id <id> --if-version <n>` refuses to overwrite a version you
  have not seen (exit 1, `conflict`).
- Nothing is deleted. `archive <id>` hides a page you are done with and
  closes it to edits; its history stays readable.

## All commands

```
artifacts publish <file|-> --title T [--id ID] [--if-version N]
artifacts list | show ID | versions ID | get ID [--version N]
artifacts state get ID [PATH] | state set ID PATH JSON | state delete ID PATH
artifacts submit ID [--payload JSON] | submissions ID [--since N]
artifacts wait ID [--since N] [--timeout SECONDS]
artifacts history ID | archive ID
```

Set `ARTIFACTS_URL` (or pass `--url`) to the host.
