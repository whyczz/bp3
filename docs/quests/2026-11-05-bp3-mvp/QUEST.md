---
status: canceled
home_repo: bp3
date: 2026-11-05
---

# bp3 MVP: the loop on itself

TL;DR
bp3 coordinates one real change to itself, end-to-end, without human
scheduling, and survives the Controller dying mid-flight. When this Quest
completes, the smallest reliable coordination loop exists: Board, brief,
visible Worker, evidence, gated auto-land, and human promotion.

ELI5
You say what you want. A Worker in its own window does it where you can
watch. The Board remembers everything, so killing the coordinator loses
nothing. Small verified pieces land themselves into a Quest branch and
report what they did; you step in once, at the end, to understand the
whole change and promote it to master.

## Goal and why

Prove the premise of bp3 on the cheapest real work available: bp3 itself.
If bp3 cannot coordinate a change to bp3, every downstream claim (lanes,
multiplexing, esc3 build-out) is fiction. Each core part gets its thinnest
working version here: protocol (packet and report ops), board (Quest,
exp, execution; idempotent reports), control (launch plus recovery
briefing), runtime (spawn one visible pi Worker with the bridge
extension, reconcile after Controller death).

## Success picture

A Worker-built `bp3 context` command, reviewed independently, auto-landed
to a Quest branch with an auditable land report, rehearsed against a
Board copy and the toy fixture, then promoted to master by the human from a
comprehension packet — with a deliberate rollback exercised once. Quest
completion is recorded here and on the Board with limitations stated.

## Scope

In: genesis kernel, toy fixture, one pi Worker shape (bridge extension,
RPC fallback), auto-land to Quest branches, Quest-to-master promotion,
self-hosting split (last promoted build runs; candidates on Board copies).
Out: lanes beyond standard, concurrency above one Worker plus one
reviewer, tokenless-waiting proofs, Muse harness, esc3 (Quest 3),
isolation, repo splits.

## Human touchpoints

Quest framing, blocker answers via briefing, Quest-to-master promotion
(the comprehension gate), and escalations (success-picture change,
budget exhaustion, integration conflict, stale downstream). Everything
else is automated or it is a design error to be logged.

## Exps

### Exp 1 — One Worker round-trip (staged 1.1-1.5)

- Intent: prove Board → brief → visible Worker → report → recovery.
- Lane: standard
- Output: genesis kernel plus toy fixture, through five substeps:
  1.1 Board/ops skeleton and `tests/toy-template/` materialization,
  read back via `bp3 context`; 1.2 visible Worker spawn (worktree,
  Zellij pane, `plugins/harness-pi/bridge` registered, endpoint on the
  Board, ready signal held, no pane text read); 1.3 brief delivered via
  the bridge and `hello` implemented on the toy repo, candidate reported
  through `bp3` ops; 1.4 missing-check blocker round-trip, steering
  through the Board inbox, pane-typing takeover detected and released,
  duplicate candidate report still exactly one result; 1.5 Controller
  killed mid-run and with a question pending, recovery briefing matches
  reality both times, Worker pane killed and reconciled stale with no
  duplicate spawn.
- Acceptance: per substep as above; all five green on the toy repo.
  Fails today: the binary does not exist.
- Depends on: none. If the 1.2 bridge spike fails, fall back to
  owned-process RPC Workers and record live view/drive as harness debt.

### Exp 2 — Auto-land with land report

- Intent: prove an exp can land itself into the Quest branch, report
  IIUC/TL;DR-style, and be refused when it should be.
- Lane: standard
- Output: gated auto-land on the toy repo: fresh reviewer Worker,
  `auto_landed` state, stored land report (TL;DR, IIUC, demos, tests,
  code pointers, revert handle), revert as a revert commit.
- Acceptance: all three refusal drills pass — failing check blocks land,
  hand-moved Quest branch blocks land as an incident, reviewer rejection
  returns as rework on the same exp.
- Depends on: Exp 1

### Exp 3 — First self-hosted change, promoted by the human

- Intent: close the Quest on real bp3 code.
- Lane: standard
- Output: `bp3 context` made real by a Worker in a bp3 worktree (next
  build only), rehearsed on a Board copy plus a green toy run, promoted
  from a comprehension packet (concept diff tour, observed demo, risks,
  rollback plan), with one deliberate rollback exercised.
- Acceptance: promotion refuses after post-authorization edits and after
  target movement; rollback restores the prior build with Board
  consistent; Quest completion recorded with limitations.
- Depends on: Exp 2

## Scorecard

Recorded from Board data once it exists: accepted/reworked/blocked exps,
human-active minutes per accepted change, interventions and repeated
explanations, Controller restarts and recovery, manual bypasses (target
zero unreconciled). Reported as friction to fix; adoption is settled and
not on trial.

## Risks and red chair

Strongest attack: a Worker exp corrupts the coordinator that would repair
it. Mitigation: running build is always the last promoted build, Board
copies for rehearsal, retained rollback, logged emergency repair.
Second attack: the bridge extension cannot honestly report settled-idle,
collapsing visible Workers into pane-watching. Mitigation: the 1.2 spike
decides early, RPC fallback is named, and the runtime never reads pane
text to decide anything. Remaining risk: three exps still hide most of
the protocol's race surface; counterexamples grow from live cases in
later exps, not from upfront design.

## Open questions

- Exact Board state enums beyond the minimum this Quest needs.
  Owner: implementer, in Exp 1.1. Recommended: working, blocked, ready,
  auto_landed, promoted, reverted — nothing more until an exp needs it.
- Zellij as the pane backend versus tmux (FirstMate's verified default).
  Owner: implementer, in Exp 1.2. Recommended: Zellij per the MVP, since
  the bridge — not the mux — carries state.

## Archived — 2026-11-07

Shelved without landing. The pane-crew center of this Quest was
retired: watchability and takeover were judged comfort, speed
(context reuse) the requirement. Execution history, exp records,
and the full disposition live on the `quest/bp3-mvp` branch.
Successors: [bp3 engine MVP](../2026-11-07-bp3-mvp-engine-core/QUEST.md),
[bp3 engine, Pi executors](../2026-11-07-bp3-engine-pi.md), and
[bp3 Pi quality of life](../2026-11-07-bp3-pi-qol.md). Dropped
gates are dropped, never passed.
