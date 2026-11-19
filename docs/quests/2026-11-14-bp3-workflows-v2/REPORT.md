# End-of-quest report — bp3-workflows-v2 (round 2: exp-6..exp-9)

Status: all 9 exps at `exp_fin` on quest branch
`bp3/goal/2026-11-14-bp3-workflows-v2`. NOT merged to
master, NOT pushed. `goal_fin` is your gate: walk the
demo, then say the word.

## Play with it (commands first)

```sh
cd /Users/whycz/m/bp3   # quest branch checked out

# 1. the whole quest at a glance: 9 exps, all landed/exp_fin
./bin/bp3 q r 2026-11-14-bp3-workflows-v2

# 2. gates
make check        # skills 94 assertions, q, worktree, tape, hooks, induct

# 3. the no-human skill (exp-8) and its fleet rules (exp-9)
cat skills/induct-goal-no-human/SKILL.md

# 4. exp-8 live evidence: dawn report of a real no-human drive
cat docs/quests/2026-11-14-bp3-workflows-v2/nodes/exp-8-induct-solo/runs/nohuman-drive-20261115/DAWN-REPORT.md

# 5. exp-9 live evidence: check-in report of a real fleet drive
cat docs/quests/2026-11-14-bp3-workflows-v2/nodes/exp-9-parallel-quests/runs/fleet-drive-20261115/CHECKIN-REPORT.md

# 6. the toys are still readable state, not screenshots
./bin/bp3 q r 2026-11-15-toy-fleet-a        # exp_fin
./bin/bp3 q r 2026-11-15-toy-fleet-b        # exp_fin
./bin/bp3 q r 2026-11-15-toy-fleet-overlap  # still todo: refused at preflight, 0 Runs
./bin/bp3 q r 2026-11-15-toy-fleet-park-a   # blocked, in inbox, your decision
./bin/bp3 q r 2026-11-15-toy-fleet-budget   # still submitted: fleet budget stopped it
./bin/bp3 worktree list                     # [] — no desks left open
```

## Exp 8 — induct-goal-no-human (landed c3, commit `75fb68f`)

Shipped as a skill mode of `induct`, not its own FSM:
the rails (preflight, park, budget, dawn report) all
state as conductor rules over the exp FSM, no special
cases, no queue-level state written. Rename complete:
`induct-solo` gone from skills, code, tests (grep
evidence in the grade matrix; skills tests pass).

Live drive, observed (conductor-run, no attestation):
queue of 3 toys — clean toy reached `exp_fin`, seeded
decision toy parked in the inbox, first dirty-tree
attempt parked on `E_DIRTY_TREE` (the conductor's own
mid-drive edits; kept as evidence, not hidden). Budget
row failed twice until a second queue
(`2026-11-15-toy-budget-stop`, stated 1-Run budget) was
run: 1 Run dispatched, exp left `submitted`, queue
stopped mid-quest. Grade c3: all 13 matrix rows pass.

## Exp 9 — parallel quests (landed c1, commit `c29715b`)

Fleet rules added to the same skill: footprint
preflight (GOAL.md Scope + exp Output; overlap = same
path or directory prefix; no declared footprint fails),
merge order declared before the queue starts, one
fleet budget, one combined check-in report, shared
decisions grouped. Skills tests: 94 assertions.

Live fleet drive, observed (check-in report quoted in
the grade matrix): fleet-a and fleet-b (disjoint) both
reached `exp_fin` in one fleet; fleet-overlap refused
at preflight with zero Runs spent (registry-verified);
park-a and park-b parked on the same decision, read as
one decision with two dependents; second fleet
(toy-fleet-budget, 1-Run budget) stopped mid-quest —
exp still `submitted`. Grade c1: all 11 rows pass.

## Human-required points

Every one is logged in
[the human log](HUMAN-LOG.md) with the best effort
made before it. Round-2 items: the round-1 `goal_fin`
gate (yours, still open), the exp-8 design approval,
and the two exp-8 resumes — both rode on your standing
"induct both experiments" instruction after the
conductor produced real evidence first.

## Scorecard (registry sums, `.git/bp3-run-registry.json`)

Round-2 drives, per quest (input/output tokens, calls):
toy-nohuman-clean 19,067,581 / 229,842 (37 calls);
toy-fleet-a 2,842,328 / 39,654; toy-fleet-b 3,045,173 /
35,923; toy-fleet-budget 296,800 / 3,421. Human-active
minutes: unmeasured, never zero. Wall time: one
evening session, 2026-11-15.

## Known warts (not hidden)

- Quest-branch tree lacks the split workflow files
  (they live on master); steps ran from `/tmp` copies.
  Candidate for its own exp.
- `goal_fin` in `bp3 q r` derives from the rollup,
  not from a promotion event; it coincides with the
  real gate only after you merge.
- Toys are fixtures on this branch: they stay readable
  as demo state; deleting them is a later cleanup call.

## The gate

`goal_fin`: your walkthrough of the demo above, then
your word. On your `goal_fin`, the conductor merges
`bp3/goal/2026-11-14-bp3-workflows-v2` to master and
pushes. Until then: nothing merged, nothing pushed.
