---
date: 2026-11-16
quest: ../QUEST.md
exp: mvp.3
status: proposed
---

# mvp.3 - ready-set-timing: cohorts and clocks

## TL;DR

Give the graph a scheduler's eyes: node deps
become machine-readable, the rollup computes BFS
cohorts and the ready set, and every node's time
is accounted — wall (first submit → land), wait
(create → first submit), dwell per state — derived
from ledger timestamps, never stored. Setup time
per Run (desk create → first bp3 answer) is
measured always; `W_SETUP_SLOW` fires locally
over 3 minutes, the agreed trigger for ever
optimizing setup. Parallel build/grade in
per-node desks is enabled by the ready set;
landing stays a serial queue.

## Demo (design trace)

```text
graph: A ─dep─► C,  B (independent),  C blocked later
rollup: cohorts [[A, B], [C]]   ready: [A, B]
A lands; C ready. C blocks -> rollup names starved: []
timing table: A wall 41m wait 0m | B wall 38m wait 2m | setup max 0.1m
```

## Diagram

```text
node deps ─► BFS layers (cohorts) ─► ready set ─► conductor dispatches
ledger ts ─► wall / wait / dwell per node ─► rollup + local gates
desk create ─► first answer: setup_wall ─► >3m -> W_SETUP_SLOW (local)
```

## Pseudocode

```python
def cohorts(nodes):
    layers, done = [], set()
    while todo := [n for n in nodes if n.state == "todo" and deps(n) <= done]:
        layers.append(todo); done |= {n.id for n in todo}
    return layers

def timing(node, ledger):
    return wall=land_ts - first_submit_ts, wait=first_submit_ts - create_ts
```

| Field | Value |
|---|---|
| Intent | speed becomes measured system behavior, not session folklore |
| Lane | standard |
| Output | deps in node records + create validation; cohort/ready/timing on rollup; local timing gates |
| Depends on | none for timing; cohort dispatch used by dogfood.2 |

## Acceptance

| Case | Expected |
|---|---|
| deps declared + cycle refused | node create with a dep cycle refuses at write time naming the cycle; deps read from node records |
| cohorts correct | a diamond graph (A→C, B→C) yields cohorts [[A,B],[C]]; ready set updates as nodes land |
| blocked blast radius | a blocked node names its starved dependents on the rollup; independent nodes stay ready |
| timing derived | wall/wait/dwell per node computed from ledger timestamps match hand-computed values on a fixture graph; nothing written to any committed file |
| setup measured | every dispatched Run reports setup_wall; a fixture with an artificial >3m setup fires `W_SETUP_SLOW` locally and only locally |
| serial land | two approved nodes land strictly one at a time; second land re-checks mergeability against the new tip |
| env-set run-id (standing ruling) | claims/env conventions unchanged; stamps as in mvp.2 |

## Acceptance test (goal block)

- **Objective:** the conductor can see what is
  dispatchable and what everything cost, from the
  system, in one read.
- **Prove by:** fixture graphs (linear, diamond,
  blocked-branch), hand-checked timing math, slow
  setup fixture.
- **Done when:** cohorts, starved sets, and
  timings are correct on fixtures, observed.

## Tests

Graph fixtures property-based: cohorts are a
topological layering (no dep in same-or-later
layer), ready set = todo nodes with deps landed.
Timing: derive twice, identical; clock only from
ledger lines. Setup gate: threshold from local
config, default 180s. Land queue: sequential
re-check fixture.

## Context

Yesterday's supervisor quest took ~9 active hours,
mostly papercut cycles and serial waiting,
discovered anecdotally. This exp makes the system
itself keep the receipts. Desks stay ad hoc (pool
killed 2026-11-16): setup is measured, and 3
minutes is the pre-agreed pain threshold.
