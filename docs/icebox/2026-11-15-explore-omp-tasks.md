---
status: frozen
date: 2026-11-15
promoted: null
---

# Explore oh-my-pi tasks: bounded delegation inside and around induct

## Context

Frozen 2026-11-15 during the pi-engine-conductor red-ink
walk, after a sidebar comparing omp's `task` concept to
bp3's Quest / exp / Run vocabulary.

An omp task is a callable unit of cognition: bounded
prompt in, schema-validated answer out, worktree
isolation, agent types (`explore`, `plan`, `reviewer`,
`task`), an Agent Hub for steering, and a concurrency
cap. Its known weakness is compression: a bounded
output hides uncertainty, failed branches, and
provenance, so a parent can over-trust a neat answer.

Our mapping, settled in that sidebar: a task is a unit
of *delegation*; a Run is a task with legal authority
and an audit obligation; an exp is the reason the Run
exists and the standard it is judged by; a Quest is
the coordinated portfolio. Tasks therefore look most
useful *around* state work (scouting, evidence,
mechanical fan-out) and questionable *inside* it
(nested children fork Run accounting).

Two open mechanics make this more than a survey:

- **Delegation from `induct-exp`:** may an author child
  use tasks to delegate sub-work (find tests, inspect
  neighboring modules, draft a subsystem)? Today it
  cannot: children are spawned without dispatcher
  tools, so grandchildren are impossible by
  construction. Whether a fenced, task-only tool —
  no `bp3 q` edges, read-mostly, budget-capped —
  earns its way into a Run is an experiment, not an
  assumption.
- **Usage tracing:** every task must leave a usage
  trail a parent can audit: which task, spawned by
  which Run, which model/thinking, tokens in/out,
  desk or read-only scope, and what its output was
  *used for*. The run event log (pi-engine-conductor
  Exp 4/Exp 8 conventions: per-Run JSONL, run-id as
  primary key) is the natural home — task rows keyed
  by a task-id under the parent run-id, folded into
  the Run's totals, never silently merging child
  self-reports into the scorecard.

## Sketch

- Survey omp task semantics first-hand (install omp
  in a scratch setup; run its bundled agents on real
  repo questions). Record what the Hub, yields, and
  isolation actually do — no vendor claims.
- Candidate trials, each timed and token-counted:
  (1) scouting tasks during quest framing / red-ink
  research (prior art, call-site maps, test inventory);
  (2) extra evidence tasks inside grade (security,
  docs-drift) next to reviewer/checker roles;
  (3) mechanical fan-out (rename sweeps, stale-term
  searches, failure classification) in the main pi
  session, outside induct;
  (4) one fenced delegation trial inside `induct-exp`,
  if and only if usage tracing below is already
  designed.
- (Added 2026-11-15, owner) Work *inside* an exp as
  tasks: coding, reviewing, linting farmed out by the
  exp child to sub-tasks — probably pi-only, since it
  presumes a task tool inside the child. Red-chaired
  the same day (see the quest framing notes): verdict
  was skills-first. Roles already *are* the task
  shapes at conductor level (author codes, reviewer
  reviews, checker checks — each a separate child with
  its own model), and skills (code-writer,
  code-reviewer) already steer a child in-process at
  zero accounting cost. A nested task boundary only
  earns its indirection for: parallel independent
  evidence, a model-divergent subtask, or bulk
  mechanical fan-out with usage traced per task.
  Linting is never a task: it is a command and a hook
  (`lint_checked` event rows exist today); paying an
  LLM process to babysit a shell command is waste.
  Any trial here still needs the usage-tracing design
  below and a fence (sub-tasks get no `bp3 q` edges,
  ever).
- Usage tracing design, on paper before any trial:
  task-id derivation, event row shapes (spawned,
  usage, settled, output-used-as), and how a grade
  matrix may cite a task's output as evidence without
  treating it as a verdict.
- Output: a keep/kill list — which omp task ideas
  enter role files or a future extension, which stay
  in omp, and the numbers behind each call.

## Blockers

- The pi engine must exist first: `bp3-pi` package,
  dispatcher tools, and the per-Run event log come
  from pi-engine-conductor; task rows and delegation
  fences build on those conventions, not before them.
- Nested-delegation accounting is unsolved on purpose:
  whose tokens, whose desk, whose tape, and whether
  a task may ever touch `bp3 q` (default answer: no)
  must be settled before trial (4) runs.
- omp is a moving fork; anything plucked is a design
  idea re-implemented against our conventions, never
  a dependency adopted wholesale.

## Promotion trigger

Thaw when pi-engine-conductor lands (`goal_fin` on
master) and either (a) a real drive shows a Run that
wanted sub-delegation and paid for lacking it, or
(b) scouting/mechanical work in the main pi session
is frequent enough that untracked task usage becomes
a cost smell. Trial (4) additionally waits for the
usage-tracing design to exist on paper.
