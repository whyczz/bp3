---
date: 2026-11-15
quest: ../QUEST.md
exp: dogfood.2
status: proposed
---

# dogfood.2 - pi-supervisor-rethink: pi engine, second draft (design)

## TL;DR

Owner-gated design exp. Rethink the pi engine
under the supervisor pattern: which parts of the
canceled pi quest survive (dispatcher, contract),
which the supervisor replaces (binding rituals,
await), and the smallest pi-engine MVP that dogfood.3
proves. Output is a decided design, not code.

## Demo (design trace)

```text
before: extension emits + hopes hooks correlate
after:  dispatcher spawns; WAL is pi session file;
        supervisor folds; watch kills; done
```

## Diagram

```text
canceled pi quest ──► keep / replace / drop table
supervisor contract ─┘        │
                              ▼
                    pi-engine MVP design (decided)
```

## Pseudocode

```python
design = decide(keep=[dispatcher, contract],
                replace=[binding, await],
                drop=[...], owner=gate)
```

| Field | Value |
|---|---|
| Intent | pi engine re-founded on the supervisor pattern |
| Lane | standard |
| Output | design record (this file, completed) + dogfood.3 brief deltas |
| Depends on | dogfood.1 (muse live proof) |

## Acceptance (fails today: pi design is the canceled quest's)

| Case | Expected |
|---|---|
| keep/replace/drop | every canceled-quest component dispositioned with reason |
| MVP shape | dogfood.3 runnable as written from the design |
| owner gate | design approved by owner before dogfood.3 |

## Acceptance test (goal block)

- **Objective:** a pi MVP design the owner has
  actually approved.
- **Prove by:** this record + owner nod recorded.
- **Done when:** disposition table complete; nod in
  the quest record.

## Tests

design exp: review is the test (red-chair the
design before approval). Known cases: each canceled
quest failure mode (unwitnessed, unsettleable,
second watchdog) maps to a named replacement or an
explicit keep. Property-based: none — design exp;
omitted deliberately, the red-chair record is the
evidence. Demos: before/after flow traces in this
record.

## Context

Teach-before-building rule applies double here:
the canceled quest is the prior art and the
cautionary tale in one.

## Auto-red-ink addendum — pi extension, fleshed out

Three components, no duplicated duties:

```text
A) bp3-pi extension (in child, fail-open)
   default(pi): choose face; resolve repo root via
     git common dir, never bare process.cwd()
   session hooks may expose in-process signals to
     the dispatcher, but write no persistent proof
   conductor face: exactly four thin tools
     (spawn_run, await_runs, list_runs, release_desk)
   NEVER: mint/parse run-id, derive lifecycle, write
     settle truth, call bp3 q u, kill, spawn
     grandchildren, widen tools/env, attest gates

B) Dispatcher (in conductor process)
   validateInput (hostile keys refused by name),
   mintRunId, loadRole, prepareDesk, spawn_run
   (semaphore; env incl. effective BP3_MODEL and
   BP3_THINKING), and hand spawn/exit facts to the
   supervisor. It does not own a second watchdog,
   lifecycle fold, or persistent event writer.

C) supervisor/supervisor (bp3 OCaml)
   find-tape, session parser, watch (sole
   killer), lifecycle fold, W_SUPERVISOR_BLIND probe.
   Sole writer of:
     bp3/run-lifecycle-derivations/<run-id>.jsonl
     bp3/run-lifecycle-derivations/<run-id>.json (cache)
   Neither A nor B duplicates C.
```

Settled defects to disposition: witness duplicates
spawn-side `run_started`; `BP3_THINKING` read but
never set; repo root bound to child cwd; two
watchdogs; two writers; settle-by-row before reap;
heartbeat gap during long tool calls; persistent
`events.ts` writer/fold duplicating the supervisor.
Do not port the witness writer, events store, TS
lifecycle fold, or dispatcher watchdog. Add a
cold-reader test: dogfood.3's brief must be executable
from this record alone. Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Pi implementation in full).
