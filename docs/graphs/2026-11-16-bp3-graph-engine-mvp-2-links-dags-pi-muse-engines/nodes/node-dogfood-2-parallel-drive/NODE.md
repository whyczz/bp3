---
date: 2026-11-16
goal: ../GRAPH.md
exp: dogfood.2
status: proposed
---

# dogfood.2 - parallel-drive: one ready-set, two flappy variants

## TL;DR

Prove BFS scheduling end to end: two independent
flappy-variant nodes in one ready-set build and grade
in parallel (separate ad hoc desks, separate
claims), then land through the serial queue. The
scorecard reports wall minutes and tokens per
node and for the ready-set — the North Star made
visible. Variants live in separate run folders so
the land queue is boring by construction.

## Demo (design trace)

```text
ready-set [flappy-day, flappy-night] (no deps between them)
  t0: both claimed, both building in parallel desks
  t1: both graded in parallel (read-only)
  t2: land flappy-day; t3: land flappy-night (serial, re-checked)
report: ready-set wall < sum(node walls); both landed
```

## Diagram

```text
        ┌─ flappy-day ──► approved ─┐
ready-set ─┤                            ├─► land queue ─► both landed
        └─ flappy-night ─► approved ─┘
one blocked variant would starve only its dependents (none here)
```

## Pseudocode

```python
desks = [adhoc_desk(), adhoc_desk()]
parallel([drive(n, desk) for n, desk in zip(ready-set, desks)])
for n in approved_in_order: land(n)   # serial, mergeability re-checked
```

| Field | Value |
|---|---|
| Intent | parallel wall-clock savings, measured; isolation without pools |
| Lane | standard |
| Output | two landed variant nodes; ready-set timing/token scorecard |
| Depends on | mvp.3, mvp.5, dogfood.1 |

## Acceptance

| Case | Expected |
|---|---|
| true parallelism | both author Runs' tapes overlap in wall time (timestamps), different desks, different claims |
| isolation | no cross-node file or context bleed (each desk's diff contains only its variant; contexts resolve per claim) |
| serial land | land edges execute one at a time; second land re-checks against the new tip and succeeds |
| scorecard honest | ready-set wall, per-node wall/tokens reported from system timing (mvp.3); ready-set wall < serial sum or the shortfall is named with cause |
| quality floor unchanged | full grade matrix per node, `make check` green; no rung skipped for speed |
| Pi tree death + revival | seed one Pi node with a human-blocking edge: its edge worker dies, node worker records `blocked` and exits, root receives one bubble, and no descendant process remains. After the owner answer + `resume`, root spawns a fresh Pi tree and the node continues; the sibling node is unaffected |
| Muse parity bubble | the equivalent Muse node workflow returns the same terminal blocked bubble and exits; revival launches a fresh workflow, never resumes the old run's agents |
| env-set run-id (standing ruling) | per-claim stamps as in mvp.2 |

## Cycle 2 fix (owner A, 2026-11-17)

Cycle-1 grade on `5140695`: parallelism,
isolation, serial land, and scorecard rows
passed; two gated rows had no coverage —
`Pi tree death + revival` and `Muse parity
bubble` inside the parallel drive. Owner
chose A: prove bubbles here. Named fix,
verbatim for cycle 2: extend the parallel
drive so one seeded node takes a human-
blocking edge in each engine form — Pi edge
worker dies, node worker records `blocked`
and exits, root receives exactly one bubble,
no descendant process remains, and after
owner answer + `resume` a fresh Pi tree
continues the node; the Muse node workflow
returns the same terminal bubble and revives
as a fresh workflow. The sibling node stays
unaffected throughout (timestamps/process
evidence, not state inference). mvp.5's base
mechanisms may be reused; the parallel-
context coverage is this exp's to prove.

## Acceptance test (goal block)

- **Objective:** two nodes land in materially
  less wall time than the serial railway would
  take, at full quality.
- **Prove by:** overlapping tape timestamps,
  land-queue ledger order, timing scorecard.
- **Done when:** both variants landed, ready-set
  wall and tokens reported from the system,
  observed.

## Tests

The drive is the test. Conflict case seeded in a
fixture (not the live drive): two nodes touching
one file must serialize at land with a named
conflict, never a silent overwrite.

## Context

The supervisor graph's 23 nodes ran strictly
serially; most followups were independent. This
is the recovery of those hours, with receipts.
Desks are ad hoc per the 2026-11-16 ruling; setup
timing watches the 3-minute gate.
