---
status: frozen
date: 2026-11-14
promoted: docs/goals/2026-11-14-bp3-cli-small-fixes/GOAL.md
---

# bp3 CLI small fixes (rendered tables, tab completion)

## Context

Frozen at the landing of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/GOAL.md),
2026-11-14, when the owner ran the quest's commands by hand
and hit two papercuts in the human-facing surface. The JSON
verdicts (the LLM surface) are fine; these are human-surface
only.

## Sketch

1. **Real tables for `--format table`.** Today the "table"
   renderer (`src/quest/render.ml`) prints `key: value` lines
   with `k=v` field dumps — a YAML-shaped thing wearing a
   table name. Replace with an actual rendered table in the
   Typer/Rich sense: aligned columns, header row, one row per
   exp (quest read) or per change (exp read), plain ASCII or
   light box-drawing so it survives any terminal. JSON stays
   the default; `tree` stays as is.
2. **Tab completion for `bp3`.** One completion script per
   shell (zsh first, bash if cheap), delivered by
   `bp3 skills install` or `bp3 init`:
   - static: verbs `c|r|u|d`, edges `submit review check land
     block resume`, flags `--format`, `--reason`, `--type`,
     `hooks`
   - dynamic: quest names, then exp names for the typed
     quest, from a fast `bp3 q` read
   Deliberately does not add: completion of commit SHAs,
   run-ids, or anything needing a full ledger fold per
   keystroke.

## Blockers

- Table renderer needs a column model per verdict shape;
  exp-read `changes` (path trees) may stay tree-only and
  the table covers the flat shapes first.
- Completion latency: `bp3 q r` spawns the OCaml binary and
  reads git refs (~tens of ms). Acceptable per keystroke,
  but completion must fail silently when the binary is
  unbuilt or the cwd is not a bp3 repo.
- Which shells matter beyond zsh is undecided (owner's
  shells first; fish only if asked).

## Promotion trigger

Thaw when the owner (or any human) is driving `bp3 q` by
hand regularly — e.g. a second hand-driven quest review
asks for the table, or muscle-memory mistakes on quest/exp
names show up in a session. Either fix also rides along
free if a CLI-surface quest opens for other reasons.
