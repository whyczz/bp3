---
date: 2026-11-15
quest: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — find-session-log: run-id <-> session <-> WAL file

## TL;DR

`bp3 harness muse|pi find-session-log --run-id <id>`
(and reverse lookups) finds the WAL file a Run
lives in: run-id, session-id, and log path resolved
per harness from run folders, session stores, and
spawn records. The lookup every other verb stands
on.

## Demo (design trace)

```text
bp3 harness pi find-session-log --run-id 2026...-submit-c1
  {run_id, harness: pi, session_id, wal: .bp3-pi/sessions/....jsonl, pid}
```

## Diagram

```text
run-id ──► run folder / spawn record ──► session-id ──► WAL path
   ▲                                                        │
   └──────────────────── reverse lookups ───────────────────┘
```

## Pseudocode

```python
def find_session_log(harness, run_id=None, session_id=None):
    for cand in wal_candidates(harness):      # session dirs per harness
        if matches(cand, run_id, session_id): return hit(cand)
    return miss(reason)                        # loud, typed
```

| Field | Value |
|---|---|
| Intent | one lookup verb, both harnesses, typed misses |
| Lane | standard |
| Output | `find-session-log` for `muse` and `pi` |
| Depends on | Exp 1 (door exists) |

## Acceptance (fails today: no lookup; humans grep session stores)

| Case | Expected |
|---|---|
| pi run from Exp-2-era spawn | WAL found by run-id |
| muse workflow child run | WAL found by run-id |
| unknown run-id | typed miss, no guess |
| two candidate files | refuse to pick; name both |

## Acceptance test (goal block)

- **Objective:** any Run's diary is one verb away.
- **Prove by:** lookups against stored corpora
  (pi quest runs; this session's children).
- **Done when:** hits for real runs, typed misses
  for fake ones.

## Tests

known cases: Acceptance table. property-based:
lookup never returns a file whose session does not
reference the run. Demos: corpus lookups observed.

## Context

Yesterday's binding saga was, in part, this lookup
done by hand with grep, repeatedly, wrong. WAL
locations: muse session store under its data dir;
pi `--session-dir` files the dispatcher controls.
