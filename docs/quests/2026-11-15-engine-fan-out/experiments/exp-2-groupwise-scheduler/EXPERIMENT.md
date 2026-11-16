---
date: 2026-11-15
quest: ../../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — Groupwise scheduler: the conductor fans out

## TL;DR

The Muse conductor stops walking one exp at a time:
for the open stage of an approved `exp_routes.json`, it
dispatches **every** actionable member concurrently —
author, grade, or land per member state, each member in
its own desk (`bp3 worktree prepare <q> <e> --run`,
inside the quest worktree) — re-reads on each return,
rides `needs_fix` cycles per member independently, and
dispatches nothing from the next stage until the barrier
(all members `landed`/`deleted`). A `blocked` member
parks the stage: siblings finish, the stage never
advances, the inbox names it. Content integration order
at `quest_fin` is contract: **stage order, then member
order as listed in routes** — the landing ceremony
applies member commits in that order, so a parallel
quest promotes as deterministically as a serial one.
Changes live in the induct skills' procedure (this is
the skill-change exp for the scheduler; step workflows
already accept `desk` since bp3-cli-small-fixes Exp 8)
and the no-human preflight (intra-quest footprint check;
fleet budget read from the run registry, not dispatch
counts).

Red-chair fixes baked in (2026-11-15): per-member desks
(one quest worktree = one index; parallel authors in it
would collide); integration order declared (parallel
landings otherwise promote by luck); stage state derived
in Exp 1, so a human `resume` reopens a parked stage
with no extra machinery.

## Demo (design trace)

```text
routes: [[A, B], [C]]    states: A todo, B todo, C todo
conductor: desks A, B -> dispatch author A + author B (concurrent)
  B submitted -> dispatch grade B        (A still building; stage 1 open)
  B landed; A needs_fix (cycle 1)        -> dispatch author A cycle 2, fix carried
  A landed                               -> barrier: dispatch author C
  C blocked                              -> stage 2 parked; siblings none; quest inbox: C
```

## Diagram

```text
open stage ─► for each member: desk + dispatch(step by state) ─► returns (any order)
     ▲                                                              │
     └────────────── re-read after every return ◄───────────────────┘
barrier: all landed/deleted ─► next stage        blocked member ─► parked (human gate, as today)
quest_fin: apply member commits in routes order (stage, then listed order)
```

## Pseudocode

```python
def conduct(quest):
    desk_q = worktree_prepare_quest(quest)
    while not terminal(quest):
        s = read(quest)                                   # includes routes.stage_state
        if s.routes.stage_state == "parked": return park(s.inbox)
        for m in actionable_members(s.routes.stage):      # state per member, as today
            dispatch(step_for(m), desk=member_desk(quest, m, inside=desk_q), run_id=fresh())
        wait_any_return()                                 # cycles ride per member, fix carried verbatim
    report(exp_fin=[...], integration_order=routes_order(quest))
```

## Tables

| Field | Value |
|---|---|
| Intent | independent exps in one stage actually run at once, without losing determinism |
| Lane | high-blast-radius (conductor procedure for every future induct; parallel writers) |
| Output | scheduler procedure in `skills/induct/SKILL.md`; fleet rails in `skills/induct-quest-no-human/SKILL.md`; renders regenerated; concurrency cases in `test/induct.sh` |
| Acceptance | cases below |
| Depends on | Exp 1 (routes, validation, derived stage state) |

| Case | Expected after |
|---|---|
| two-member stage, both todo | both authors dispatched before either returns (fixture observes interleaved run_started registry entries) |
| one member lands, other building | no next-stage dispatch (barrier held, observed in dispatch log) |
| member `needs_fix` below cap | that member cycles with the named fix; the sibling is never re-dispatched or held |
| member blocked | siblings complete; stage parks; quest stops; inbox names the member and reason |
| human resume of parked member | stage reopens from derived state; only the resumed member dispatches |
| overlapping footprints (routes edited post-approval) | Exp 1 validation refuses dispatch; scheduler never starts the group |
| quest without routes | dispatch pattern identical to today (serial, one step per read) |
| parallel writes | no index/branch collisions: members' commits land on separate desks/branches; shared-tree `git status` unchanged during the run |
| quest_fin integration | member commits applied in routes order; a deliberately conflicting-order fixture lands in listed order, not completion order |

## Acceptance test (goal block)

- **Objective:** a grouped stage runs concurrently,
  barriers and parks hold, and promotion stays
  deterministic.
- **Prove by:** a two-quest fixture — one grouped quest
  driven through a full stage with registry timestamps
  proving overlap, one serial quest as control; the
  blocked-park and resume traces; the integration-order
  fixture at a scratch `quest_fin`; `make check` green.
- **Done when:** overlap is observed (not inferred),
  the barrier never leaks a dispatch, and the serial
  control's dispatch sequence is unchanged from today.

## Prose

Context: the conductor's serial rule ("exactly one step
per read") is policy in the induct skill, not engine
law — the step workflows are already stateless per exp.
This exp changes the policy where routes authorize it
and nowhere else. Why member desks are per-exp runs of
the existing prepare, not a new primitive: the worktrees
quest built exactly this (S1/S3) and Exp 8 of the prior
quest wired `desk` into every step; the missing piece
was only ever the conductor's willingness to have two
steps in flight. Why integration order is routes order:
completion order is timing, and timing is not a merge
strategy — the author of the routes file already
declared the only order a human has reviewed. Budget:
the no-human fleet budget becomes a registry read
(settled + unsettled runs) because a counting conductor
cannot count what it dispatched in parallel honestly.

## Tests

unit: none · fixtures: concurrency/barrier/park/resume/
integration-order cases in `test/induct.sh` with scratch
quests and stubbed step timing · demos: the design trace
run live on a scratch quest at review, registry quoted
