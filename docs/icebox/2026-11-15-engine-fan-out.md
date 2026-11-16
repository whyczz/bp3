---
status: frozen
date: 2026-11-15
promoted: null
---

# Engine fan-out (parallel experiments, typed engine contract)

## Context

Frozen 2026-11-15, right after the landing of
[bp3-cli-small-fixes](../quests/2026-11-14-bp3-cli-small-fixes/QUEST.md),
when the owner watched a Muse induct run and asked why it
is so linear. Today the conductor
([induct skill](../../skills/induct/SKILL.md)) dispatches
exactly one step per read and walks the railway serially:
exp author -> grade -> land, then the next exp. The one
parallel shape that exists — the fan-out group — is
exploration-only and never landable, and the conductor
stops to ask a human which members run. Meanwhile a Pi
engine quest is being built in parallel
(`docs/quests/2026-11-15-pi-engine-conductor`), so whatever
fan-out means, two engines will need to speak it.

The question the owner froze: does induct need to be
linear? Not a DAG — can the group be widened and fanned
out, with the contract between conductor and engine
**typed**, starting with Muse and designed so Pi can
implement the same shape?

## Sketch

Refined by the owner the same day (2026-11-15), railway
style: the railway stays **linear**, but each stage is a
**parallel group**. The plan lives up front in an authored
`exp_routes.json` in the quest folder, written at framing
time and `proposed` until the owner approves it:

```json
{
  "quest": "2026-11-15-some-quest",
  "status": "proposed",
  "stages": [
    { "stage": 1, "exps": ["exp-1-tables", "exp-2-completion"] },
    { "stage": 2, "exps": ["exp-3-icebox"] },
    { "stage": 3, "exps": ["exp-4-help", "exp-5-release"] }
  ]
}
```

Stage semantics: every exp in a stage is dispatched
concurrently (own worktree each — see Blockers); a stage
is done when all members are `landed`/`deleted`; only
then does the next stage dispatch. A member hitting
`blocked` parks the stage: siblings finish, the stage
never advances, the quest parks with it. No DAG, no
dependency edges between exps — the stage list *is* the
ordering, and grouping is the only parallelism claim.
The engine validates the file at preflight: every exp
named exactly once, all exps exist, `status` approved
before any dispatch. `exp_routes.json` is plan, not
state — the ledger stays truth, exactly as `fsm.yaml`
relates to `state.yaml` today.

The smallest version that would work:

- A **fan-out group** on the railway: a named set of exps
  declared independent (disjoint footprint, no `depends_on`
  between members), run concurrently — one author per exp,
  each in its own worktree (Exp 8's quest worktree becomes
  one desk per exp inside it, or per-Run desks).
- The conductor stops being a loop and becomes a
  **scheduler over a typed contract**: the engine (Muse
  workflows today, Pi next) receives step dispatches and
  returns verdict-shaped results; the conductor only reads
  `bp3 q r`, applies the contract, and dispatches what
  states call for. Contract sketch (to be settled, not
  assumed): `dispatch {quest, exp, step, desk, run_id,
  commit?}` -> `result {exp, outcome, commit, run_ids,
  refusals}` — the shapes the three induct workflows
  already return, named as a contract instead of three
  private conventions.
- Grades may fan out with their authors: independent exps
  grade concurrently; `land` stays serial per quest (state
  edges are CAS on shared refs, lands are cheap).
- Deliberately does **not** add: a DAG planner, dependency
  inference from diffs, cross-quest scheduling (the fleet
  already does quests in parallel), or auto-merge of
  conflicting footprints — an overlapping group member is
  refused at declaration, not merged.

## Blockers

- Footprint disjointness is currently prose (Scope tables);
  fan-out needs it machine-checked, or "independent" is a
  hope. The no-human preflight already refuses overlapping
  quests; the same check must work *within* a quest.
- The three step workflows return similar but uncontracted
  shapes; Pi is being built against them right now — every
  week of delay raises the cost of typing the contract.
- Grade children within one exp already run audit/review/
  check concurrently in one worktree; fanning out exps
  multiplies `_build`, test, and tape contention per desk
  (the dune `--root` wart was the first taste).
- Cycle semantics under parallelism: two members hitting
  `needs_fix` at once is fine (disjoint), but a shared
  Makefile/skill file that both must edit is a hidden
  dependency the declaration missed — who detects it, and
  does the group park or serialize?
- Run budget accounting (no-human fleet budget) assumes a
  roughly serial dispatch order; parallel burn needs the
  registry to be the source, not the conductor's count.

## Promotion trigger

Thaw when any of these is observed:

- A quest with 4+ independent exps spends most of its
  wall-clock with the conductor idle-waiting on one child
  (scorecard wall time vs child run times in the registry);
- The Pi engine quest reaches the point of implementing
  step dispatch — the contract must be typed before Pi
  hard-codes the linear shape; or
- The owner runs two Muse inducts by hand in parallel
  because the serial one is too slow, and they step on
  each other's quests.
