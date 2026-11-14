# Icebox

Future quests, frozen with enough context to thaw.

An icebox entry is not a quest. It is a quick sketch — today's
context, the shape of the thing, and every blocker we already
know — so that when we are ready, promoting it to a Quest with
`/quest` is transcription, not archaeology.

## Entry shape

- **Context**: what we were designing when this froze, with links.
- **Sketch**: the smallest version that would work.
- **Blockers**: what must be true or decided first.
- **Promotion trigger**: the signal that says “thaw this now.”

Entries live flat here as `YYYY-MM-DD-<slug>.md`. Nothing in
this folder is state; the ledger never points here. When an
entry thaws, it becomes a Quest under `docs/quests/` and the
entry is marked `promoted: <quest path>` — never deleted.
