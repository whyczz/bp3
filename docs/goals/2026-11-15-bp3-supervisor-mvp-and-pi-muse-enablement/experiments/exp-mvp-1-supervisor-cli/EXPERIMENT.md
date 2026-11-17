---
date: 2026-11-15
goal: ../GOAL.md
exp: mvp.1
status: proposed
---

# mvp.1 - supervisor-cli: the game loop

## TL;DR

`bp3 harness supervisor` exists: one OCaml loop in
the binary (not a shell script) that ticks — fold
Run evidence, derive lifecycle, act (dispatch,
watch, kill, surface) — until the quest is done,
a timeout fires, or a human gate opens.

## Demo (design trace)

```text
bp3 harness supervisor toy --timeout-seconds 1800
  tick: A active / B finished / C silent 601s -> KILL
  exit: done (all finished) | timeout | human gate
```

## Diagram

```text
        ┌────────────── tick ──────────────┐
        ▼                                  │
  fold WAL+pid ─► derive lifecycle ─► act ─┘
        exit: all finished | timeout | blocked inbox non-empty
```

## Pseudocode

```python
def supervisor(quest, timeout):
    while not expired(timeout):
        view = fold_all(quest)
        if terminal(view): return Done(view)
        if view.inbox:     return HumanGate(view.inbox)
        act(next_step(view))          # spawn / watch / kill
        sleep(tick)
```

| Field | Value |
|---|---|
| Intent | the loop as CLI path; single deriving/acting rhythm |
| Lane | standard |
| Output | `bp3 harness supervisor` (OCaml) + tick/exit semantics; code/tests use `init_record` and lifecycle strings `init/active/finished/orphaned` — no `SpawnRecord`, `spawned`, `running`, or lifecycle `settled` synonyms |
| Depends on | none |

## Acceptance (fails today: no harness door, no loop)

| Case | Expected |
|---|---|
| toy quest, all settle | loop exits `done` without LLM polling |
| child never settles | timeout exit, orphans named |
| blocked exp appears | loop exits at human gate with inbox |
| env-set run-id (owner amendment, cycle 2) | `BP3_RUN_ID` arrives via environment, never a child-typed command prefix: bp3 reads it on `q` invocations and stamps it into the verdict JSON and the ledger line (same env channel as `BP3_HARNESS`/`BP3_MODEL`). Grade evidence for the Run is that stamped ledger line; the hooks registry witness does not gate this exp — InitRecord (mvp.8) and the supervisor fold own proof |

## Acceptance test (goal block)

- **Objective:** a loop that babysits Runs
  mechanically and stops for exactly three reasons.
- **Prove by:** toy quest drive with one slow and
  one hung child.
- **Done when:** exits observed for done + timeout
  + gate paths.

## Tests

known cases: Acceptance table (fake children);
exit-class mapping (RC4): each outcome maps to the
binary's existing exit classes — settled=0,
watchdog_killed=terminal, timeout=retryable,
human_gate=needs-human — asserted per outcome.
env run-id: with `BP3_RUN_ID` set, a `bp3 q`
verdict and its ledger line carry that run-id;
unset, the field is absent (never guessed) with
the existing identity warning.
naming gate: grep new code/tests for retired
lifecycle spellings (`SpawnRecord`, `spawned`,
`running`, lifecycle `settled`) and require the
`init/active/finished/orphaned` set.
property-based: tick is idempotent — same fold,
same action. Demos: toy drive observed.

## Context

Game-engine shape per owner: fixed tick, state
derived per frame, no event callbacks trusted.
The loop is one invocation; killing and rerunning
it loses nothing (all state is folded).

## Auto-red-ink addendum

This exp splits into 1.1 (door + verdict/exit
contract, fixture-proven) and 1.2 (active loop,
proven only after mvp.2-mvp.3). Tick phases are named
`tell -> watch -> judge (fresh bp3 q r) -> finalize`.
The supervisor never signals a pid and never
finalizes from a watch outcome. For Muse, no
active supervisor loop is built; the passive
supervisor derivation is shared. Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Supervisor core: stream, verdict split, guarded
act, single killer, restart derivation, inputs).
