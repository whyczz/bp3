---
date: 2026-11-15
quest: ../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — await-watchdog: the monitor grows teeth

## TL;DR

Awaiting a Run blocks in code, never in an LLM:
race process exit, WAL growth, and sentinel fold.
Cross the silence budget and the watchdog escalates
SIGTERM -> SIGKILL; the killed Run derives
`orphaned`, never `settled`. (The canceled quest's
Exp 2b, rehomed under the sentinel.)

## Demo (design trace)

```text
await(run) ... WAL silent 601s ... SIGTERM ... SIGKILL
-> RunOutcome{outcome: killed, settled: false}
```

## Diagram

```text
await ── race ── proc exit ──────┐
              ├─ WAL settle row ─┼─► terminal outcome
              ├─ fold says done ─┤
              └─ silence > budget ─► TERM ─► KILL ─► orphaned
```

## Pseudocode

```python
async def await_run(run, silence_s):
    async with race(exit(run), wal_events(run), fold_poll(run)):
        if silent_for(silence_s): kill(run, TERM, grace, KILL)
    return outcome(run)   # settled only on evidence
```

| Field | Value |
|---|---|
| Intent | blocking await + silence watchdog, both engines' conductors consume it |
| Lane | standard |
| Output | await in pi dispatcher + sentinel-backed await for muse reads |
| Depends on | Exp 2, Exp 4 |

## Acceptance (fails today: await hangs on stuck children)

| Case | Expected |
|---|---|
| clean child | await resolves on exit, settled per evidence |
| hung child | TERM then KILL inside budget; `settled:false`; no live process left |
| slow-drip child | WAL growth resets silence clock; never killed mid-work |
| blind WAL | pid-only await still terminates the hung child; warning attached |

## Acceptance test (goal block)

- **Objective:** no await ever blocks forever, and
  no killed child reads as success.
- **Prove by:** fake-pi variants (clean/hung/drip)
  + one real hung drive.
- **Done when:** all rows green; hung drive leaves
  no process behind.

## Tests

known cases: Acceptance table. property-based:
randomized drip under budget never triggers;
randomized silence over budget always does.
Demos: hung drive observed on tape.

## Context

Ecosystem prior art agrees (PiFlow, Orbi,
billion-context): parent-side silence watchdog,
TERM -> KILL. Pi core itself hangs indefinitely on
a dead provider (earendil-works/pi#6581); no child
self-kill exists anywhere — supervision is the
parent's job by design.
