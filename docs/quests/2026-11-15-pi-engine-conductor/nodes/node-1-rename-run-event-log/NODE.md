---
date: 2026-11-15
goal: ../QUEST.md
exp: 1
status: proposed
---

# Exp 1 — rename registry to run event log, everywhere

## TL;DR

Owner-ruled at red-ink: the store formerly called the
registry is a run event log — append-only per-Run event
rows, folded on read. This exp does the rename across
docs and codebase as the quest's first exp, so every
later exp is born speaking the new word. Words and
identifiers only: the storage migration (per-Run files)
is Exp 8. A synonym left behind means the rename has
not happened.

## Diagram

```text
registry (word, type, file, fn names)
  src/quest/hooks.ml      registry_path, load/save_registry
  test/hooks.sh           registry() helper
  skills/**/workflows     "`.git/bp3-run-registry.json`"
  docs, skills, records   prose mentions
        |  one sweep, one commit series
        v
run event log / RunEventRow / .git/bp3-run-events.json
(legacy file still read, named legacy; fossils —
tapes, committed ledger history, git history — untouched)
```

| Field | Value |
|---|---|
| Intent | one concept, one word, one spelling, everywhere it lives |
| Lane | standard (rename across src, tests, skills, docs) |
| Output | renamed identifiers, file name, and prose; grep proof; `make check` green |
| Depends on | none — this is the first exp by owner's ruling |

## Acceptance (fails today: `grep -ri registry src test skills docs` hits everywhere)

| Case | Expected |
|---|---|
| word sweep | `grep -ri "registry" src/ test/ skills/ docs/quests/2026-11-15-pi-engine-conductor/QUEST.red-ink.md` returns only named legacy/fossil mentions (legacy file fallback, historical records), each marked as such |
| code names | no `registry` identifier in `src/quest/*.ml` or workflow scripts; event-log names compile and tests pass |
| behavior identical | same rows, same readers: a muse Run before and after the rename produces equivalent event evidence (hooks tests unchanged in what they assert, only in what they call it) |
| legacy file | an existing `.git/bp3-run-registry.json` is still read, reported as `legacy`, never silently renamed or merged |

## Acceptance test (goal block)

- **Objective:** the rename is total and behavior-free.
- **Prove by:** the grep above + `make check` + one
  live muse step Run emitting event-log-named evidence.
- **Done when:** grep clean (legacy/fossil only), gates
  green, live Run's evidence reads in the new words.

## Tests

known cases: the Acceptance table · property-based:
none — grep closure is the property (stated plainly) ·
fixtures: hooks tests, skills tests · demos: the live
Run, observed.

## Substep 1.2 — worktree → desk in code (owner, post-adoption)

Same treatment for the older word. "Desk" is already
the concept everywhere in this Quest; the code still
says worktree. Rename in one sweep, callers updated in
the same change (no alias left behind):

| Today | After |
|---|---|
| `src/quest/worktree.ml` | `src/quest/desk.ml` |
| `bp3 worktree <verb>` | `bp3 desk <verb>` (prepare/check/exit/release/list keep their names) |
| `.bp3/worktrees/<quest>/<exp>/<run_id>` | `.bp3/desks/<quest>/<exp>/<run_id>` (quest desk: `.bp3/desks/<quest>/conductor`) |
| `test/worktree.sh` | `test/desk.sh` |

Live `.bp3/worktrees/` directories on disk are
machine-local and derived: new derivation points at
`.bp3/desks/`; pre-rename desks stay listable and
releasable through the legacy path until released,
never silently moved. Acceptance mirrors 1.1:
`grep -ri worktree src/ test/ skills/` (outside
fossils and the legacy-path shim) is empty, `make
check` green, one live desk prepared and released
under the new names.

## Context

Renaming late is how Tower-of-Babel happens (the
induct-solo rename cost a cycle in the previous quest
because the old word had spread). Doing it first, while
the new storage is still unbuilt, means Exp 2's
conventions and Exp 4's pi writer never write the old
word at all.
