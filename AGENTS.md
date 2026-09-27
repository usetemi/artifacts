# Artifacts

A persistent, provider-agnostic host for live HTML pages that people and
coding agents build together.

@DOMAIN.md
@DESIGN.md

Codex and other harnesses that do not expand `@` imports: read `DOMAIN.md`
and `DESIGN.md` in full before starting work.

`DOMAIN.md` is the source of truth for the ubiquitous language and the
domain rules. Use its terms, follow its rules as written, and revise
`DOMAIN.md` first before introducing a concept, workflow, or policy absent
from it. `DESIGN.md` says how each rule is built; revise it with the code.

Read `server/AGENTS.md` before working in `server/`. Its usage-rules block
is generated: change the `usage_rules` config in `server/mix.exs` and run
`mix usage_rules.sync`, never edit the block by hand.
