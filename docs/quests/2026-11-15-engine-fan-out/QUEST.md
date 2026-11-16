---
status: proposed
home_repo: bp3
date: 2026-11-15
---

# engine-fan-out: linear stages, parallel groups

TL;DR
The railway stays linear, but each stage becomes a
parallel group: an authored `exp_routes.json` (proposed
until the owner approves it) declares stages up front,
the engine validates it, and the Muse conductor
dispatches every member of the open stage concurrently —
each in its own worktree — advancing only at the stage
barrier. The step contract (`Dispatch`/`Result`) is typed
once here so Pi, being built in parallel, implements the
same shapes instead of a second convention. Promoted
from [the engine fan-out icebox entry](../../icebox/2026-11-15-engine-fan-out.md);
promotion per the `quest` skill: transcription, not
adoption — scope re-decided at framing (Muse first;
Pi conformance is that quest's work, named below).

ELI5
Today a quest is a single-file line: one experiment
finishes before the next starts, even when they never
touch each other. This quest makes the line a series of
stations where several experiments can be worked on at
the same time, then all must finish before the train
moves on.

## Terms

| Term | One line |
|---|---|
| `exp_routes.json` | authored file in the quest folder: `{quest, status, stages[]}`; plan, not state (ledger stays truth) |
| Stage | one entry in `stages`: a parallel group of exp ids; stages run in list order |
| Stage barrier | the next stage dispatches only when every member of the open stage is `landed` or `deleted` |
| Parked stage | a stage with a `blocked` member: siblings finish, the stage never advances, the quest parks |
| Dispatch | the typed step request `{quest, exp, step, desk, run_id, commit?}` a conductor sends an engine |
| Result | the typed step reply `{exp, outcome, commit, run_ids, refusals}` (grade adds `matrix`); the shapes the three induct workflows already return, now named |
| Member desk | one worktree per exp inside the quest worktree (parallel authors never share an index) |
| Footprint disjoint | within one stage, no two members' declared Output paths overlap (checked, not hoped) |

## Demos

### Observed — the serial cost (2026-11-15)

```text
bp3-cli-small-fixes induct, Exp 2 author child: ~9 minutes wall
during which Exps 3-8 sat in todo, conductor idle.
The quest's own Exp 3 submit later refused E_DIRTY_TREE from
parallel human work — the collision this quest's desks prevent.
```

### Design trace — groupwise run (nothing here has run yet)

```text
exp_routes.json: stages [[exp-1, exp-2], [exp-3], [exp-4, exp-5]]
conductor: prepare member desks -> dispatch exp-1 + exp-2 (concurrent)
  exp-2 lands; exp-1 still building     -> stage 1 open, nothing new dispatches
  exp-1 lands                           -> barrier: dispatch exp-3
  exp-3 blocked                         -> stage 2 parks; quest inbox shows it
```

## Goal and why

The owner, watching a Muse induct run: "it's really
linear — does it need to be?" The exps in most quests are
independent in clusters, so serial dispatch wastes the
wall clock and teaches owners to run parallel sessions by
hand (which collide). Groupwise stages capture the real
dependency shape — clusters, not chains — without a DAG.
Typing the contract now is the Pi play: a second engine
is being built against these workflows, and an untyped
convention hardens into two dialects.

## Success picture

A quest framed with a multi-exp stage inducts with those
exps building, grading, and landing concurrently in
separate worktrees; the barrier holds; a blocked member
parks cleanly; a quest with no `exp_routes.json` behaves
byte-identically to today.

## Scope

| In | Out |
|---|---|
| `exp_routes.json` schema, validation, and current-stage read in `bp3 q` | a DAG planner; dependency inference from diffs; cross-quest scheduling (fleet already does it) |
| Groupwise conductor scheduling in Muse (induct + no-human preflight/budget) | Pi's implementation of the contract (pi-engine-conductor quest owns it; this quest types what it consumes) |
| Per-member desks via existing `bp3 worktree prepare <q> <e> --run` | new worktree machinery; merging overlapping footprints (refused at validation) |
| `/quest` framing writes `exp_routes.json` (default: one exp per stage = today's railway) | retrofitting routes onto landed quests |

## Human touchpoints

Quest approval (this file; approval also marks the
icebox entry promoted); routes approval is per-quest at
framing (`status: proposed -> approved`), never the
engine's call.

## Exps

### Exp 1 — [Routes contract](experiments/exp-1-routes-contract/EXPERIMENT.md)
`exp_routes.json` typed and validated: schema in
`store.ml`, preflight verdicts for bad files, `bp3 q r`
reads the open stage. No parallelism yet — the contract
must be checkable before anything runs concurrently.
Depends on: none. Lane: standard.

### Exp 2 — [Groupwise scheduler](experiments/exp-2-groupwise-scheduler/EXPERIMENT.md)
The induct conductor dispatches all open-stage members
concurrently (member desk each), rides `needs_fix` cycles
per member, parks on a blocked member, advances at the
barrier. No-human preflight checks intra-quest footprints;
budget reads the run registry. Skill changes ride here as
the mechanism's own exp (workflows already take `desk`).
Depends on: Exp 1. Lane: high-blast-radius.

### Exp 3 — [Routes framing](experiments/exp-3-routes-framing/EXPERIMENT.md)
`/quest` writes `exp_routes.json` at framing (grouping
asked like acceptance is), exp records name their stage,
skill tests assert it. Depends on: Exp 1 (Exp 2 not
required: framing can precede the scheduler).
Lane: standard.

### Exp 4 — [Integration order](experiments/exp-4-integration-order/EXPERIMENT.md) (follow-up)
Red-chair follow-up: `quest_fin` applies member commits
in routes order (stage, then listed order), parks on
conflict naming the member pair, resumes without
re-applying. Depends on: Exp 2. Lane: standard.

### Exp 5 — [Routes amendments](experiments/exp-5-routes-amendments/EXPERIMENT.md) (follow-up)
Red-chair follow-up: closed stages immutable, open stage
frozen at first dispatch, future stages editable with
re-approval bound to the routes hash. Depends on:
Exps 1–2. Lane: standard.

### Exp 6 — [Member desk lifecycle](experiments/exp-6-member-desk-lifecycle/EXPERIMENT.md) (follow-up)
Observed-wart follow-up: engine plumbing dirt
(`ledger.jsonl`/`state.yaml` in a member desk after land)
is classified as generated, refreshed at release, never
again a `--force`; author dirt still refuses. Desks are
released at the stage barrier. Depends on: Exp 2.
Lane: standard.

Exps 4–6 form stage 3 of this quest's own routes: all
depend only on Exp 2, footprints disjoint.

## Scorecard

| Field | Value |
|---|---|
| Wall time | unmeasured until Runs record it (the trigger metric: wall vs summed child time) |
| Context tokens | unmeasured per-Run until hooks tally them |
| Human-active minutes | approval + one hand-watched parallel demo |

## Risks and red chair

Red-chair pass at the icebox (2026-11-15), verdict
fix-first; attacks and what they changed:

| Attack | Change it made |
|---|---|
| One quest worktree can't host parallel authors (one HEAD/index) | member desks per exp are the primary shape (Exp 2); quest desk is only the container |
| "Independent" is prose; engine checks only quest-level `depends_on` | footprint-disjoint + routes validation are engine-checked in Exp 1, before any concurrency exists |
| Splitting into parallel quests already works for free | kept as the named alternative: this quest wins on shared quest context and not pre-sharding the owner's work; if a framed quest never groups, Exp 3's default keeps it serial at zero cost |
| Typed contract bought before its customer (Pi) exists | contract frozen as documentation of today's return shapes in Exp 1; the scheduler (Exp 2) is Muse-only until Pi's implementation can object |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Promotion trigger: Pi implementing dispatch is in flight (trigger arguably fired); wall-clock idle evidence is one quest's scorecard, not three. Owner directed promotion directly. | human (directed 2026-11-15) |
| 2 | Does Pi adopt `Dispatch`/`Result` verbatim, or does pi-engine-conductor settle a dialect this quest must then chase? | human (with the Pi quest) |
| 3 | Is `promoted:` set on the icebox entry at this Quest's approval, per the `quest` skill? | human (approval does it) |
