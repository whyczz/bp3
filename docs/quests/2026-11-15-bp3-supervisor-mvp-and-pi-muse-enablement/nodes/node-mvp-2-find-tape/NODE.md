---
date: 2026-11-15
goal: ../QUEST.md
exp: mvp.2
status: proposed
---

# mvp.2 - find-tape: run-id <-> session <-> tape

## TL;DR

`bp3 harness muse|pi find-tape --run-id <id>`
(and reverse lookups) finds the WAL file a Run
lives in: run-id, session-id, and log path resolved
per harness from run folders, session stores, and
init records. The lookup every other verb stands
on.

## Demo (design trace)

```text
bp3 harness pi find-tape --run-id 2026...-submit-c1
  {run_id, harness: pi, session_id, wal: .bp3-pi/sessions/....jsonl, pid}
```

## Diagram

```text
run-id ──► run folder / init record ──► session-id ──► WAL path
   ▲                                                        │
   └──────────────────── reverse lookups ───────────────────┘
```

## Pseudocode

```python
def find_tape(harness, run_id=None, session_id=None):
    for cand in wal_candidates(harness):      # session dirs per harness
        if matches(cand, run_id, session_id): return hit(cand)
    return miss(reason)                        # loud, typed
```

| Field | Value |
|---|---|
| Intent | one lookup verb, both harnesses, typed misses |
| Lane | standard |
| Output | `find-tape` for `muse-code` and `pi`, incl. pointer resolution: `--entry <id>` returns the one digest-verified entry, widened by `--before-entries/--after-entries <n>` |
| Depends on | mvp.1 (door exists) |

## Acceptance (fails today: no lookup; humans grep session stores)

| Case | Expected |
|---|---|
| pi run from Exp-2-era spawn | WAL found by run-id |
| muse workflow child run | WAL found by run-id |
| unknown run-id | typed miss, no guess |
| two candidate files | refuse to pick; name both |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** any Run's diary is one verb away.
- **Prove by:** lookups against stored corpora
  (pi quest runs; this session's children).
- **Done when:** hits for real runs, typed misses
  for fake ones.

## Tests

known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). property-based:
lookup never returns a file whose session does not
reference the run. Demos: corpus lookups observed.

## Context

Yesterday's binding saga was, in part, this lookup
done by hand with grep, repeatedly, wrong. Session
log locations: muse session store under its data
dir; pi `--session-dir` files the dispatcher
controls.

## Auto-red-ink addendum

Lookup is InitRecord-first. Run-id is the sole
primary key; session-id is a reverse lookup input
that must resolve to exactly one run-id. Both,
neither, or disagreeing identity flags are
`E_USAGE`; misses are `E_NOT_FOUND`; ambiguity is
named and refuses. Pi lookup must not port the
existing last-file-wins `discoverSession`.
Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Supervisor core inputs; Muse discovery; Pi
session parser inputs).
