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
entry thaws, its context is copied into the quest under
`docs/quests/`, the entry gains `promoted: <quest path>`, and it
is then deleted — git history is the fossil (owner rule,
2026-11-15). An unpromoted entry is never deleted.

Standing rule (owner, 2026-11-17): whenever a quest or graph
is written from an icebox entry — and at every promotion —
copy the entry **verbatim** to `ICEBOX.md` in the quest/graph
folder before the original is deleted. Never transcribe it
into prose; the frozen file travels as-is.
