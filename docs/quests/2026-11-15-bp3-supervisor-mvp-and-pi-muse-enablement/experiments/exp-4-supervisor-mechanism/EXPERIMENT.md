---
date: 2026-11-15
quest: ../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — supervisor-mechanism: bp3 runs on it (muse first)

## TL;DR

bp3 adopts the supervisor as its operating
mechanism for muse: induct steps spawn and watch
Runs through `bp3 harness`; lifecycle reads fold
WAL + mailbox; the shared mutable witness dict is
replaced by per-Run `.jsonl` mailboxes.

## Demo (design trace)

```text
induct-exp child spawned -> watch returns settled
-> conductor re-reads bp3 q r -> dispatches grade
(zero hook-ritual instructions in the child brief)
```

## Diagram

```text
induct ─► harness supervisor/watch ─► child (muse)
              │ fold WAL+mailbox
              ▼
        bp3 q r lifecycle view (derived)
```

## Pseudocode

```python
def step(exp):
    run = spawn(exp)                 # harness path
    out = watch(run.run_id)          # Exp 3
    return step_result(out, bp3_q_r(exp))
```

| Field | Value |
|---|---|
| Intent | supervisor is the mechanism, not a side tool (muse path) |
| Lane | high-blast-radius |
| Output | induct integration + per-Run mailbox writer (muse) |
| Depends on | Exp 1-3 |

## Acceptance (fails today: hooks ritual + shared dict)

| Case | Expected |
|---|---|
| toy exp via supervisor | travels todo -> landed; lifecycle from fold |
| child never told any prefix | witnessed anyway (WAL-derived) |
| parallel Runs | per-Run files, zero shared-dict writes (legacy mtime static) |

## Acceptance test (goal block)

- **Objective:** one toy exp lands with the
  supervisor as the only witness machinery.
- **Prove by:** toy drive; mailbox + WAL traces.
- **Done when:** landed, traces shown, dict retired
  on the write path.

## Tests

known cases: Acceptance table; `make check` suites.
property-based: parallel emits lose zero rows.
Demos: toy drive observed.

## Context

This is where hooks demote to footprint-leavers
and the canceled quest's Exp 8 (per-Run storage)
lands as a substep of mechanism adoption rather
than its own quest.
