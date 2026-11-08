---
status: proposed
home_repo: bp3
date: 2026-11-07
---

# bp3 engine MVP: concepts, tested with Muse + workflows

TL;DR
bp3 gains its engine concepts — a contract judged on context rent,
and a state machine whose states are clean commits plus Board
metadata — proven by test on Muse workflows, the fastest honest
testbed available. When this Quest lands, the toy exp travels
author → review → land as commit-states taken by workflow
children, measurably cheaper than today's fresh-context Pi crew.

ELI5
Today every helper starts blank and pays full price to re-learn the
job; that rent, not typing speed, is the wait. So the coordinator
keeps the map in its own head, sends out helpers that inherit or
fork what it knows, and writes down what happened. You read the
summary, not the workshop floor.

## Goal and why

Replace the pane-crew execution model with an engine model whose
contract is context provisioning: `cold | warm | fork | subagent`.
The predecessor Quest
[bp3 MVP: the loop on itself](2026-11-05-bp3-mvp.md) proved the
Board, brief/report ops, and gated landing, but its center bet —
fresh-context Workers in watched Zellij panes — makes every Run
re-buy its context. Four-hour coder/reviewer bounces were observed;
the human judges watchability and takeover to be comfort, speed the
requirement. This Quest keeps the proven record and landing layers
and rebuilds only how work executes.

## Success picture

The four hours are attributed with numbers; today's Pi launcher
sits behind a named engine contract with zero behavior change; and
the commit-state machine runs the toy exp end to end on Muse
workflow children — author edge, review edge, land — with guards
intact. Landing is recorded here with the baseline breakdown, the
measured context cost per edge, and limitations. Assumption: the
Board (OCaml/SQLite) survives as the record layer; if Exp 1 shows
it is the bottleneck instead, that becomes an open question for
the human, not a silent rewrite.

## Scope

In: a timed baseline of the current Pi loop; extracting today's Pi
launcher behind an engine contract with zero behavior change; the
commit-state FSM concepts (states, edges, guards, registry
flavors); and testing all of it with Muse + workflows as the
first executor. Inherited by reference: the archived Quest's Exp 2
auto-land kernel candidate `9e1b1d0` and its gated-landing
contract. Sibling Quests: [bp3 engine, Pi executors](2026-11-07-bp3-engine-pi.md)
(oh-my-pi, subagent extensions, or our own) and
[bp3 Pi quality of life](2026-11-07-bp3-pi-basics.md) (the Pi speed
meta), written alongside this one.
Out: warden/hook substrate (decided: not yet; the contract sketch
waits in the [hooks dossier](../dossiers/muse-workflows-hooks.md)),
resurrecting pane takeover as a requirement (Zellij remains a
debug view only), foreign-TUI typing, multi-host or remote Workers,
arbitrary per-Quest graph editing (a DAG), and any change to the
frozen Exp 2 coordinator before its kernel is adopted or dropped
by explicit human decision.

## Human touchpoints

Quest framing (this file), escalations (success-picture change,
budget exhaustion, engine contract change), and Quest-to-master
promotion. Everything else is automated or it is listed here.

## Exps

### Exp 1 — Timed baseline: where the four hours go

- Intent: attribute the current loop's cost before changing it.
- Lane: standard
- Output: a recorded breakdown for one toy exp on today's Pi crew:
  framing, spawn-to-ready, context load, execution, checks, review,
  and idle-blocked time, plus context tokens per Run.
- Acceptance: the breakdown exists with numbers observed from Board
  timestamps and session usage. Fails today: the archived Quest's
  scorecard records human-active minutes and provider cost as
  unmeasured, and the Board snapshot hardcodes cost to null.
- Substeps: 1.1 add token/usage accounting to the snapshot (turn
  events with input/output/cache tokens); 1.2 run one toy exp and
  publish the phase breakdown; 1.3 state the verdict: context,
  ceremony, provider, or scheduling dominates. If ceremony or
  provider dominates, this Quest archives early with that finding.
- Depends on: none.

### Exp 2 — Engine contract, Pi-as-is extracted

- Intent: name the seam without behavior change.
- Lane: standard
- Output: today's launcher behind an explicit engine contract
  (reserve, prepare worktree, spawn, deliver, steer, cancel,
  snapshot; signals ready/heartbeat/busy/settled/observed/
  took_over/release/permission/exited with opaque endpoints), with
  each Run recording its context provisioning mode. Zero behavior
  change to the frozen Exp 2 path; the extraction lives on a
  separate branch/worktree until adopted.
- Acceptance: toy substeps 1.1–1.5 stay green, unchanged, on the
  extracted Pi engine, `bp3 context` shows the provisioning mode
  per Run, and the Pi/Zellij argv exists only inside the Pi engine
  implementation. Fails today: no engine contract exists; the Pi
  argv and Zellij calls are hardcoded in the launcher.
- Depends on: Exp 1 (the baseline this must not regress).

### Exp 3 — Commit-state FSM: the engine concepts

- Intent: define state and moves so any executor can play.
- Lane: high-blast-radius
- Output: state = (clean commit SHA, Board metadata: kind,
  verdicts, evidence, generation); edges author/review/fix/land
  with guards (clean tree, HEAD equals the state commit, verdict
  bound to the exact commit, cycle/budget bounds, generation
  fencing). Flavors live in a code registry with lane presets —
  micro: author → checks → land; standard: author ↔ review, at
  most 3 cycles; high: design gate → author ↔ review → explicit
  stop. New flavors are code changes with tests, never runtime
  graph editing. A reviewer refactor is a fix edge producing a
  new state with provenance, never an in-place edit of another
  executor's worktree.
- Acceptance: two executors alternate edges on one exp with
  identical guard behavior; a verdict on commit A is refused
  after commit B supersedes it; the machine halts at its bound
  and escalates instead of ping-ponging. Fails today: states are
  process labels, one live Run Board-wide, no roles, reports
  accepted unconditionally.
- Depends on: Exp 2.

### Exp 4 — Concepts test: Muse + workflows as first executor

- Intent: prove the concepts on the fastest honest testbed before
  Pi executors exist.
- Lane: standard
- Output: the toy exp executed by a Muse main session whose
  workflow children take FSM edges and report through Board ops,
  plus probes: the V8 engine actually executes on this machine; a
  child can (or cannot) reach the bp3 CLI through its tool grant;
  per-call model routing fails as documented and the
  separate-parent workaround is priced. Background:
  [Muse workflows dossier](../dossiers/muse-workflows-hooks.md).
- Acceptance: a child takes the author edge and a fresh child the
  review edge against the same commit-state; block is honored as
  block-then-respawn with no lost question; context cost per edge
  recorded against Exp 1 — lower, or the test records why not.
  Fails today: no Muse engine, no saved workflows, no live run.
- Depends on: Exp 3. Block/resume stays out unless the test proves
  steering live.

## Scorecard

Per exp and per engine: wall time intent-to-land, context tokens
per Run (provisioning mode noted), human-active minutes,
interventions and repeated explanations, review/rework cycles, and
manual bypasses. Recorded here and in each exp record from Board
data and session usage; unmeasured values are stated, never zero.

## Risks and red chair

- Strongest attack on the goal: "engine" conflates harness,
  topology, and transport. What changed: the contract is defined by
  context provisioning and the report/land ops, not by brand;
  harness and fan-out shape are recorded per Run.
- Strongest attack on order: the baseline is Exp 1 because the
  four-hour bounce is unattributed; if ceremony or provider limits
  dominate, engines change nothing and this Quest should archive
  early with that finding. Remaining open: whether watchability's
  loss hides a real debugging need the debug view cannot cover.

## Open questions

1. Does Exp 1 verdict (context, ceremony, provider, scheduling)
   keep this Quest alive at all? Owner: human, at the Exp 1 gate.
   An archive-early outcome is a success, not a failure.
2. Block/resume versus block-then-respawn. Default: respawn.
   Owner: human, with Exp 4 evidence.
3. May a reviewer take a fix edge, or only authors? Default: yes,
   as a new commit-state with provenance; verdicts still require
   a fresh reviewer. Owner: human, before Exp 3.
4. How fat may the engine contract grow before it encodes Pi-pane
   assumptions? Default: no new signal kinds without a second
   engine needing them. Owner: implementer, in Exp 2.
