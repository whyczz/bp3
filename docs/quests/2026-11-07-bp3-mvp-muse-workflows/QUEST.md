---
status: proposed
home_repo: bp3
date: 2026-11-07
---

# bp3-mvp-muse-workflows: Muse as an engine executor

TL;DR
Muse workflows become a tested engine executor: a main Muse
session fans out to workflow children that take commit-state
edges through bp3 invoke, under the same guards Pi faces. When
this Quest lands, the toy exp travels author → review → land on
workflow children, with context cost per edge measured against
the core baseline.

ELI5
The core built the relay track and the baton. This quest enters
a new kind of runner — Muse workflow children — and checks it
plays by the same rules: finished commits only, verdicts glued
to the commit reviewed, no sneaking around the ledger.

## Concepts

- commit-state — (clean commit, stage, cycle) in a quest folder;
  the only thing passed between executors.
- edge — a named move taken through `bp3 invoke` (submit, review,
  check, land, block, cancel), ledgered even when refused.
- executor — whoever takes an edge: Pi session, subagent, or
  Muse workflow child. Interchangeable by design.
- workflow child — an ephemeral Muse subagent spawned by a
  workflow script; unsteerable mid-flight, reports once.

## Goal and why

[bp3-mvp-engine-core](../2026-11-07-bp3-mvp-engine-core/QUEST.md)
proves the state machine. Muse is where the human already runs
a main session daily, and its workflow API offers in-process
fan-out that could kill the fresh-context tax — if ephemeral,
unsteerable children can honor a contract built on durable
state. This Quest tests that on the toy fixture before any Pi
executor work depends on the answer. Background:
[Muse workflows and hooks dossier](../../dossiers/muse-workflows-hooks.md).

## Success picture

The toy exp travels end to end on workflow children: one child
takes the author edge, a fresh child the review edge, checks and
CAS land follow, all through `bp3 invoke` with `--actor` naming
each child. A commit-state authored by a workflow child is
reviewed by a different executor kind unchanged. Context cost
per edge is recorded against the core baseline.

## Scope

In: the Muse executor test, live probes of the workflow API on
this machine (V8 execution, child CLI reach, model routing),
block-as-respawn behavior, and the interchange test. Out:
steering a running child, per-call model routing inside one
workflow (documented absent; separate parents are the priced
workaround), and any change to core guards.

## Human touchpoints

Quest framing, escalations (API limits that break the contract),
and Quest-to-master promotion.

## Exps

### Exp 1 — Muse executor test

- Intent: test whether ephemeral workflow children can take FSM
  edges.
- Lane: standard
- Output: the toy exp executed by a Muse main session whose
  workflow children take edges and report through `bp3 invoke`,
  plus three probes: the V8 engine actually executes on this
  machine; a child can (or cannot) reach the bp3 CLI through its
  tool grant; per-call model routing fails as documented and the
  separate-parent workaround is priced.
- Acceptance: a child takes the author edge and a fresh child
  the review edge against the same commit-state; block is
  honored as block-then-respawn with no lost question; context
  cost per edge recorded against the core Exp 1 baseline —
  lower, or the test records why not. Fails today: no Muse
  engine, no saved workflows, no live run.
- Depends on: bp3-mvp-engine-core Exps 2–3 (scaffold, FSM).
  Block/resume stays out unless the test proves steering live.

### Exp 2 — Interchange with Pi states

- Intent: prove the baton crosses executor kinds.
- Lane: standard
- Output: the interchange fixture: workflow-authored commit-state
  reviewed by a Pi executor, Pi-authored state reviewed by a
  workflow child, identical guards both directions.
- Acceptance: both directions pass with no guard relaxed and no
  state translated by hand. Fails today: no Muse executor, no
  Pi executor (bp3-engine-pi Quest owns the Pi side).
- Depends on: Exp 1; bp3-engine-pi Exp 4.

## Scorecard

Per edge: wall time, context tokens by child, human-active
minutes, refused moves, and probe outcomes (V8, CLI reach,
routing). Recorded here and in exp records; unprobed claims are
stated as claims.

## Risks and red chair

- Strongest attack: building on a versioned, partly
  reverse-engineered workflow API rebuilds bp3 inside a harness
  feature. What changed: Muse is an executor behind the core
  contract, never the record layer; if the API breaks, one
  executor dies, the machine does not.
- Strongest attack: ephemeral children cannot block-and-resume,
  so the blocker contract leaks. What changed: block-then-respawn
  is the specified behavior, with the question ledgered; resume
  is revisited only if steering proves live.
- Remaining open: whether child tool grants reach the bp3 CLI
  reliably enough for edges, or the parent must relay reports.

## Open questions

1. Block/resume versus block-then-respawn. Default: respawn.
   Owner: human, with Exp 1 evidence.
2. Do children report through the CLI directly, or relay via the
   parent session? Default: direct if grants allow. Owner:
   implementer, in Exp 1.
3. Separate parents per model tier — worth the session cost?
   Default: measure in Exp 1 before adopting. Owner: human.
