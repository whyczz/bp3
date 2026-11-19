---
status: frozen
date: 2026-11-19
promoted: null
---

# Retire slow suites by coverage map (test-pyramid retire.1, deferred)

## Context

Deferred 2026-11-19 from the test-pyramid quest
(`docs/quests/2026-11-18-test-pyramid/`, node retire.1, record at
`nodes/node-retire-1-coverage-map/NODE.md`). Owner, verbatim: "nah bro
this code is barely being used, i am the only dogfooder, i want to use
it, not wait for 2 weeks and spend a gorillion tokens".

By then the quest's speed goal was met without deleting anything:
`make check` went from about 160s to about 7s (lint, dune test, the JS
unit tier), and `make check-full` runs every suite in about 37s
against a 60s target. retire.1 would shrink the slow suites further:
map every old suite's assertions onto the new tiers, prove each
deletion loses nothing with planted mutations, then delete.

## Sketch

As the node record specifies, unchanged:

- `test/COVERAGE.md`: one row per old suite, each cluster mapped to the
  new test that covers it, or kept with a one-line reason.
- `test/MUTATIONS.md`: at least 10 planted mutations, each run against
  the old suites and the new tiers; no row may read "old caught, new
  missed".
- New tests land before the deletion commit, and the owner reads both
  tables before it.
- `make check-full` stays at 60s or less, five runs in a row.

Known gaps found during the run, input for the map: induct-grade's
tests miss three mutants (verify_verdict ignored, todo -> ship, default
max_cycles), and parts of `dep_satisfied` have no claimed coverage.

## Blockers

- Cost: a high-blast-radius node (it deletes tests), so a deep grade
  is warranted. That is worth it only when the slow suites hurt again.
- test/worktree.sh's parallel prepare flaked once in 10 check-full runs
  under load. Fix or explain it before any deletion leans on the gate.

## Promotion trigger

`make check-full` creeps past 60s, or a slow suite flakes twice in a
week.
