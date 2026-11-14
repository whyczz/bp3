---
status: frozen
date: 2026-11-14
promoted: null
---

# Muse workflows MVP v2: one workflow per state transition

## Context

Frozen after the
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/QUEST.md)
landing, 2026-11-14. The bootstrap engine used one fat
workflow — `induct-exp` reads state, builds every child
prompt, authors, submits, reviews, checks, lands, and loops
until terminal. That shape was scaffolding: when it was
written there was no trustworthy engine yet, so one
invocation had to carry the whole ceremony.

It worked, and it dogfooded the quest to landed. It also
has the costs the owner felt: a large blast radius, no way
to rerun just the grade against a submitted commit, FSM
branching duplicated in JS even though `bp3 q` owns legal
moves, and long invocations that consume several child
Runs before returning control to the conductor.

Now that `bp3 q` holds state externally in git, the JS no
longer needs to own the lifecycle. This entry freezes the
v2 shape for when it is worth rebuilding.

## Sketch

The conductor owns the loop; workflows become step
functions — read current state, do exactly one stage,
return.

```text
induct (skill, main session)
  loop: read state via bp3 q r
    todo      -> induct-exp     build + commit + submit; return
    submitted -> induct-grade   evidence audit + review/check; return
    approved  -> land step      one tiny ceremony Run
    blocked   -> human inbox
    landed    -> next exp on the railway
```

- Every step Runs from a prepared worktree desk
  (`bp3 worktree prepare`, per the bp3-worktrees quest):
  author on the exp branch, graders detached at the bound
  commit, conductor's tree never moved.
- `induct-exp` shrinks to implementation only: author
  child, clean commit, `submit` edge. It never judges.
- `induct-grade` is new and judge-only: no edits, no
  fixes. It runs the evidence audit (one row per
  acceptance case, exact observed artifact or `missing`),
  then review and check children in parallel, binding
  their edges to the exact submitted commit. Missing
  required evidence is `needs_fix` or `blocked`, never an
  inferred pass; evidence that cannot be produced in the
  current environment (e.g. hooks not loaded because the
  session predates `.muse/hooks.json`) is
  `blocked: evidence unavailable`, not a pass.
- Landing stays a tiny step after `approved`; whether it
  is a mini-workflow or a single conductor-dispatched
  child is decided at promotion.
- Workflows stay stateless and parameterized
  (`{quest, exp, ts, harness, model}`); state is rebuilt
  from `bp3 q` on every invocation, so any step can be
  rerun or resumed after a dead session without the
  previous invocation's memory.
- Quest-level functional/E2E judgment stays out of these
  workflows: it belongs to the landing pass
  (`red-ink-quest-landing-demo`), after the railway.

TODO — two-level worktree closing (owner, 2026-11-14):

- Run level is the normal path: each build/grade step's
  child exits its own worktree on clean settle
  (`bp3 worktree exit`). If it blocks with dirty work,
  checkpoint first when possible; otherwise preserve the
  worktree and surface its path in the human inbox.
- Quest level is the audit/sweep: when `induct` finishes
  or the quest lands, the conductor lists all worktrees
  for the quest, releases clean stragglers, and treats
  any dirty worktree as a landing blocker until a human
  decides. After correct Run-level exits, this sweep
  should normally find zero.

## Blockers

- Grade contract must be designed, not just moved: the
  evidence-audit shape, its run record, and how review /
  check children consume its matrix without an FSM edge
  of their own.
- Run/tape conventions per step: run-ids, env preset, and
  tape folders currently assume the monolith's stage
  names; the split must keep them derivable.
- Worktree isolation is owned by the
  [bp3-worktrees quest](../quests/2026-11-14-bp3-worktrees/QUEST.md):
  v2 consumes its `bp3 worktree` verbs (author desk on the
  exp branch, grader desks detached at the bound commit)
  rather than inventing isolation mid-split. This quest
  lands first, or v2's Exp on adoption absorbs proving it.
- Migration: `induct-exp.js`, its mock-host contract test
  (`test/induct-exp.test.mjs`), and the `induct` skill
  text all describe the monolith and move together.
- Whether grade may run under a different model/effort
  than implementation is unprobed on this harness.

## Promotion trigger

Thaw when any of these is observed: a grade needs
rerunning without re-entering implementation; a workflow
dies mid-lifecycle and recovery is awkward; per-Run token
cost of the monolith becomes a measured complaint; a
second engine or harness needs the same step contract; or
the next quest after the MVP opens the engine for changes
anyway.
