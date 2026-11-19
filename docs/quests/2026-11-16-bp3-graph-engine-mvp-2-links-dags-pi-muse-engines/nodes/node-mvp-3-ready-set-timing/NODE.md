---
date: 2026-11-16
goal: ../QUEST.md
exp: mvp.3
status: proposed
---

# mvp.3 - ready-set-timing: ready-set waves and clocks

## TL;DR

Give the graph a scheduler's eyes: node deps
become machine-readable, the rollup computes BFS
ready-set waves and the ready set, and every node's time
is accounted — wall (first handoff → land), wait
(create → first handoff), dwell per state — derived
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
rollup: ready-set waves [[A, B], [C]]   ready: [A, B]
A lands; C ready. C blocks -> rollup names starved: []
timing table: A wall 41m wait 0m | B wall 38m wait 2m | setup max 0.1m
```

## Diagram

```text
node deps ─► BFS layers (ready-set waves) ─► ready set ─► conductor dispatches
ledger ts ─► wall / wait / dwell per node ─► rollup + local gates
desk create ─► first answer: setup_wall ─► >3m -> W_SETUP_SLOW (local)
```

## Pseudocode

```python
def ready-set waves(nodes):
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
| Output | deps in node records + create validation; ready-set/ready/timing on rollup; local timing gates; `induct-node` worker contract (Muse workflow run; recursive Pi root -> node session -> edge session) emitting one terminal outcome per node |
| Depends on | none for timing; ready-set dispatch used by dogfood.2 |

## Acceptance

| Case | Expected |
|---|---|
| deps declared + cycle refused | node create with a dep cycle refuses at write time naming the cycle; deps read from node records |
| ready-set waves correct | a diamond graph (A→C, B→C) yields ready-set waves [[A,B],[C]]; ready set updates as nodes land |
| blocked blast radius | a blocked node names its starved dependents on the rollup; independent nodes stay ready |
| timing derived | wall/wait/dwell per node computed from ledger timestamps match hand-computed values on a fixture graph; nothing written to any committed file |
| setup measured | every dispatched Run reports setup_wall; a fixture with an artificial >3m setup fires `W_SETUP_SLOW` locally and only locally |
| serial land | two approved nodes land strictly one at a time; second land re-checks mergeability against the new tip |
| dep freeze explored | deps stay mutable-but-logged through this node; any schedule anomaly caused by a mid-flight dep edit is recorded with the node/cycle, and the record proposes the freeze rule (or none) from that evidence |
| node-worker shape | Muse dispatches one `induct-node` workflow per ready node; Pi root session spawns one node-worker session per ready node and that session spawns edge sessions. Both forms own the node's FSM loop and return exactly one terminal outcome (`landed`, `blocked`, or `deleted`) to the root |
| env-set run-id (standing ruling) | claims/env conventions unchanged; stamps as in mvp.2 |

## Acceptance test (goal block)

- **Objective:** the conductor can see what is
  dispatchable and what everything cost, from the
  system, in one read.
- **Prove by:** fixture graphs (linear, diamond,
  blocked-branch), hand-checked timing math, slow
  setup fixture.
- **Done when:** ready-set waves, starved sets, and
  timings are correct on fixtures, observed.

## Tests

Graph fixtures property-based: ready-set waves are a
topological layering (no dep in same-or-later
layer), ready set = todo nodes with deps landed.
Timing: derive twice, identical; clock only from
ledger lines. Setup gate: threshold from local
config, default 180s. Land queue: sequential
re-check fixture.

## Context

Yesterday's supervisor graph took ~9 active hours,
mostly papercut cycles and serial waiting,
discovered anecdotally. This exp makes the system
itself keep the receipts. Desks stay ad hoc (pool
killed 2026-11-16): setup is measured, and 3
minutes is the pre-agreed pain threshold.
