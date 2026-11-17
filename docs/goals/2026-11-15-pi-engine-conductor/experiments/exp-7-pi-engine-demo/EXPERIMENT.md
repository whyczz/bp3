---
date: 2026-11-15
goal: ../GOAL.md
exp: 7
status: proposed
---

# Exp 7 — pi-engine-demo: the quest-level proof

## TL;DR

The landing demo for the pi engine: `/induct` inside pi
drives one fresh toy quest end-to-end and a two-quest
fleet (parallel children, disjoint desks), ending in a
check-in report — the same evidence standard the muse
fleet met. Then the red-ink-goal-landing-demo runs and
this Quest stops at its `goal_fin` gate.

## Demo (design trace)

```text
/induct toy-pi-a, toy-pi-b        (one pi session)
  preflight: footprints disjoint -> both admitted
  fleet: children in desks, in parallel
  toy-pi-a exp_fin; toy-pi-b exp_fin
  check-in: goal_fin list in declared order,
            parked: none, tokens per quest (event log),
            worktree sweep []
```

| Field | Value |
|---|---|
| Intent | prove the engine whole, once, in public |
| Lane | standard |
| Output | drive record + check-in report under `runs/`; landing demo record in the Quest file |
| Depends on | Exp 3, 4, 5, 6 |

## Acceptance (fails today: pi has never driven a quest)

| Case | Expected |
|---|---|
| full drive | both toy quests at `exp_fin`, all ledger lines `harness: pi` |
| parallel honesty | the two author Runs' event log windows overlap in time (parallel, not interleaved theater) |
| scorecard | report carries tokens per quest from the event log; human-active minutes stated or "unmeasured" |
| gates | `make check` green on the landed tree; worktree sweep `[]` |

## Acceptance test (goal block)

- **Objective:** a stranger can watch pi induct and
  believe it.
- **Prove by:** the live drive + `bp3 q r` on both
  toys + event log overlap query.
- **Done when:** both toys `exp_fin` with overlapping
  Run windows and the report quoted in the Quest file.

## Tests

known cases: Acceptance table · property-based: none —
the live drive is the test (stated omission) · demos:
this exp is the demo.

## Context

This is the exp the earlier pi quest never reached: it
proposed a three-way bake-off and no drive. Here the
bake-off is demoted to design input (Exp 2's pluck
notes) and the drive is the gate. If the fleet window
shows no overlap, the exp fails honestly and the
dispatcher's concurrency claim goes back to Exp 1.
