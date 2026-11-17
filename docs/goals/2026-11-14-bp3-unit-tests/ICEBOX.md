---
status: frozen
date: 2026-11-14
promoted: docs/goals/2026-11-14-bp3-unit-tests
retired: 2026-11-15 (owner: retire/delete the icebox; this verbatim fossil in the quest folder is the record, git history the other)
---

# OCaml unit and property-based tests for bp3 q

## Context

Frozen at the landing of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/GOAL.md),
2026-11-14, when the owner asked "where are the unit tests?"
The honest answer: there are none at the OCaml level. Every
check is an end-to-end shell fixture (`test/q.sh`,
`test/hooks.sh`, `test/tape.sh`, `test/skills.sh`) or a
mock-host JS test (`test/induct-exp.test.mjs`). The fixtures
are good — they caught real defects — but the pure core
(fold, CAS contention, ledger round-trips, hook payload
mapping) has no fast, targeted tests, and nothing
property-based anywhere.

## Sketch

- Alcotest suite under `src/quest/test/` (dune test),
  wired into `make check`, covering the pure seams:
  - `store`: ledger line encode/decode round-trip; fold
    over synthetic ledgers (edges, event lines skipped,
    cycle counting, blocked/resume); state derivation from
    branch-tip files
  - `hooks`: payload → event-kind mapping table; env-preset
    regex (first-match-wins, conflicts); stale-gate boundary
    (899s vs 901s); dedupe keys
  - `render`: verdict shapes per `--format` (golden strings)
- One property-based layer (QCheck) only where a law
  exists: fold is order-determined by the ledger; event
  lines never change folded state; CAS loser never writes.
  No generators for their own sake.
- Shell fixtures stay: they are the acceptance level.
  This entry adds the unit level under them, it does not
  replace them.

## Also frozen here: the process change

Not just bp3's own gap — the standard that prevents the
next one. When this thaws, also change how exps are framed
(`/quest` skill, exp record shape):

- Every exp states its **test split** up front, next to the
  failing-today acceptance: unit cases (named, and failing
  today or labeled characterization), acceptance fixtures,
  demos. Three levels, three audiences: unit guards the
  seam for the next refactor, fixtures gate the landing,
  demos show the human.
- An exp may declare **no unit tests**, but only as a
  stated one-line decision (docs-only, pure glue, seam
  already covered) — never as an omission.
- The exp tables gain a `Tests` line, separate from the
  Acceptance goal block.

Backfilling bp3's existing core is the Sketch above; the
standard applies to new exps from thaw day, not
retroactively.

## Blockers

- `store.ml`/`hooks.ml` were not written for testability:
  some pure functions sit next to git/process calls and
  may need seam extraction (small refactor, no behavior
  change) before they can be unit-tested.
- QCheck/Alcotest availability in the local opam switch is
  unverified; adding deps needs a pin decision.
- Nobody has measured fixture runtime pain yet — `make
  check` is seconds today, so the speed argument is weak
  until the suite grows.

## Promotion trigger

Thaw when any of: a fold/ledger defect escapes the shell
fixtures into a real quest; `make check` grows slow enough
that a fast unit layer pays rent; or a refactor of
`store.ml`/`hooks.ml` needs a safety net finer than the
end-to-end fixtures.
