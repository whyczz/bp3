---
date: 2026-11-15
goal: ../GOAL.md
exp: mvp.4
status: proposed
---

# mvp.4 - supervisor-mechanism: bp3 runs on it (muse first)

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
    out = watch(run.run_id)          # mvp.3
    return step_result(out, bp3_q_r(exp))
```

| Field | Value |
|---|---|
| Intent | supervisor is the mechanism, not a side tool (muse path) |
| Lane | high-blast-radius |
| Output | induct integration + per-Run mailbox writer (muse) |
| Depends on | mvp.1-mvp.3 |

## Acceptance (fails today: hooks ritual + shared dict)

| Case | Expected |
|---|---|
| toy exp via supervisor | travels todo -> landed; lifecycle from fold |
| child never told any prefix | witnessed anyway (WAL-derived) |
| parallel Runs | per-Run files, zero shared-dict writes (legacy mtime static) |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** one toy exp lands with the
  supervisor as the only witness machinery.
- **Prove by:** toy drive; mailbox + WAL traces.
- **Done when:** landed, traces shown, dict retired
  on the write path.

## Tests

known cases: Acceptance table; `make check` suites;
env-set run-id is stamped by bp3 into the submit
verdict and ledger line (the mvp.1 mechanism).
property-based: parallel emits lose zero rows.
Demos: toy drive observed.

## Context

This is where hooks demote to footprint-leavers
and the canceled quest's Exp 8 (per-Run storage)
lands as a substep of mechanism adoption rather
than its own quest.

## Auto-red-ink addendum

Muse mechanism means passive supervisor derivation,
not spawn/watch control: Muse's workflow runtime
remains the completion owner. Split 4b (run
event log migration) restores the canceled quest's
rows: per-Run writer, reader fold, run-id re-keying
with session-id demoted to a field, legacy read-only
with named sunset, no silent merge. Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Muse implementation, esp. runtime
non-interference and the grader evidence ladder).
Local storage follows the QUEST layout: only
`<git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl`
(supervisor observations + lifecycle) and its
disposable `<run-id>.json` state cache. Raw facts
stay in harness tapes; legacy run-event files
are read-only imports, never new write targets.
Deletion of the replaced machinery is mvp.5, not
this exp.
