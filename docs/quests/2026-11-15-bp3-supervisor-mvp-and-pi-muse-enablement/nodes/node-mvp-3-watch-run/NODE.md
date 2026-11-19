---
date: 2026-11-15
goal: ../QUEST.md
exp: mvp.3
status: proposed
---

# mvp.3 - watch-run: blocking done-signal with teeth

## TL;DR

`bp3 harness muse|pi watch --run-id <id>` (or
`--session-id`): find the WAL, then block in code —
process exit, WAL growth/settle markers — until
terminal state or timeout. Silence past budget:
SIGTERM, grace, SIGKILL. Returns one typed outcome;
an LLM never polls.

## Demo (design trace)

```text
bp3 harness watch --run-id R --silence-seconds 600
  -> {outcome: killed, settled: false, last_wal_growth_s: 611}
```

## Diagram

```text
find WAL ─► race: proc exit | WAL settle | fold poll
                     └ silence > budget ─► TERM ─► KILL
            ─► typed RunOutcome (settled only on evidence)
```

## Pseudocode

```python
def watch(run, silence_s, timeout):
    wal = find_tape(run)
    while not terminal(run):
        if wal.silent_for(silence_s): kill_escalate(run)
        wait_next_event(run, wal)
    return outcome(run)
```

| Field | Value |
|---|---|
| Intent | the await primitive for both engines' conductors |
| Lane | standard |
| Output | `watch` verb for `muse` and `pi` |
| Depends on | mvp.2 |

## Acceptance (fails today: no watch; awaits hang)

| Case | Expected |
|---|---|
| clean child | watch returns on exit, settled per evidence |
| hung child | TERM/KILL inside budget; `settled:false`; no process left |
| slow-drip child | WAL growth resets silence; never killed mid-work |
| WAL missing | typed blind outcome + `W_SUPERVISOR_BLIND`, pid still watched |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** no watch blocks forever; no
  killed child reads success.
- **Prove by:** fake children (clean/hung/drip)
  per harness + one real hung drive.
- **Done when:** rows green; no process survives.

## Tests

known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). property-based:
drip under budget never kills; silence over budget
always does. Demos: hung drive observed.

## Context

The pi core hangs indefinitely on a dead provider
(earendil-works/pi#6581); every ecosystem answer is
a parent-side watchdog. This exp makes ours a verb.

## Auto-red-ink addendum

Watch is the sole TERM/KILL owner. Add the
closed-but-not-exited case: session closed or a
settle row suspends the silence kill; the overall
timeout still applies. Blindness asserts
`warnings:["W_SUPERVISOR_BLIND"]`, never a blind
outcome. Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(watch verdict split, settling grace, watchdog
escalation, invalid durations, blind fallback).
