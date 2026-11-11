---
quest_type: default
engine: single
status: proposed
home_repo: bp3
date: 2026-11-09
---

# bp3-mvp-plugin-git-cas-lands: the landing clerk as a skill

TL;DR
A `/land` skill lands one quest at a time onto a moving master:
rebase onto the target *before* review, then submit, review,
check, and compare-and-swap through `bp3 invoke`. When this
Quest lands, landing a quest is a skill run, not a human
driving git by hand, and the binary's CAS edge is the only
step that moves the branch. Rebasing after review (the full
retry loop) is hardened later in
[bp3-land-verdicts](../2026-11-09-bp3-land-verdicts/QUEST.md).

ELI5
Master keeps moving while quests work. Landing is the last inch:
put your commit on top of whatever master is now, prove the
checks still pass on that exact commit, then move master in one
atomic step that fails safely if someone else moved it first.
A person can do this once; a skill does it the same way every
time and writes down what happened.

## Concepts

- land skill — this Quest's output: a skill that conducts one
  quest's landing. Instructions only; it never writes state.
- compare-and-swap (CAS) — `git update-ref <target> <new> <old>`:
  move the branch only if it is still at `<old>`. Already the
  binary's `land` edge; this Quest consumes it, unchanged.
- stale — a quest commit whose base is no longer the target's
  head. Stale commits rebase and re-validate before landing.
- evidence chain — review/check verdicts bound to one exact
  commit. A rebase mints a new commit and restarts the chain.
- landing clerk — the queue role for multiple ready quests.
  Named here, built nowhere in this Quest: MVP is one quest
  at a time, so ordering is a non-problem until it is real.
- plugin (in this Quest's name) — the binary-side git surface
  the follow-up Quest builds (landing packet, error envelope,
  CAS hardening). The MVP half delivered here is the skill;
  no plugin code is scoped in this Quest.

## Goal and why

[bp3-mvp-engine-core](../2026-11-07-bp3-mvp-engine-core/QUEST.md)
built the state machine and its CAS `land` edge against a
mostly-static master. Real use is several quests in flight
against a master that moves under them. Somebody must rebase
stale work onto the target before its evidence chain starts,
drive the CAS land, and stop — not improvise — when the
target moves mid-landing. That conductor is judgment
and choreography, not state — so it is a skill, while the
atomic move stays in the binary, the only writer of state.

## Success picture

On the toy fixture, a quest whose base went stale before
review lands cleanly: the skill rebases its commit onto the
current target *before* `submit`, so review and checks bind
to the rebased commit, then takes `land --target` and the
target ref verifiably moves to that commit, with a ledger
line per step and no human touching git. If the target moves
between review and land, the CAS refusal stops the landing
and escalates — the skill does not loop in this Quest; that
retry loop is the follow-up's hardening. Landing is recorded
in the quest ledger; the skill transcript is evidence, never
state.

## Scope

In: the `/land` skill (single quest, single target); rebase
onto the target before `submit` so the evidence chain binds
to the landed commit; always landing with an explicit
`--target` (the default path moves no ref); conflict →
`block` edge escalation; CAS refusal → stop and escalate;
worktree release and branch cleanup after a successful land.
The skill stamps its edges `--actor land-skill`, parses only
JSON stdout (never stderr text), and documents that `invoke`
reads refresh `state.yaml` (derived cache; read the JSON,
never the file).
Out: rebasing after review or at stage `ready` (no legal
edge accepts a rebased commit there today — hardened in
[bp3-land-verdicts](../2026-11-09-bp3-land-verdicts/QUEST.md));
CAS retry loops; multiple quests landing concurrently and
any ordering across them (MVP is one quest at a time);
speculative merge queues; binary changes of any kind; the
binary performing rebases; silent conflict resolution.

## Human touchpoints

Quest framing (this file), conflict escalations the skill
raises through `block`, and Quest-to-master promotion.
Everything else is the skill's loop or it is listed here.

## Exps

### Exp 1 — Land skill: rebase before review

- Intent: prove the narrowed loop end to end on today's
  binary: stale work is rebased onto the target before the
  evidence chain starts, so every verdict binds to the
  commit that lands.
- Lane: standard
- Output: `skills/land/SKILL.md` (installed per the repo's
  skill flow; declares its `jq` dependency) that, given a
  quest at `author`/`fix` and a target branch: reads state
  through `bp3 invoke`; rebases the quest commit onto the
  target head in the quest's worktree; runs `submit` on the
  rebased commit; lets review/`check` proceed on it; takes
  `land --target <branch>` (always explicit); and verifies
  the target ref moved to the submitted commit.
- Acceptance: on the toy fixture, move the target after the
  quest commit is authored but before `submit`; run the
  skill; observe: the submitted, reviewed, and checked
  commit is the rebased one, the target ref equals it after
  `land`, and one ledger line exists per edge. Fails today:
  no land skill exists; a stale commit can only be landed
  by hand, and nothing rebases or re-validates it.
- Depends on: bp3-mvp-engine-core's `land` edge (landed in
  code on the quest branch).

### Exp 2 — Refusal stop, conflict block, cleanup

- Intent: the skill fails safely on the two failures it can
  meet before the follow-up Quest hardens the loop.
- Lane: standard
- Output: skill behavior for (a) CAS refusal because the
  target moved between review and land: stop, surface the
  refusal verbatim to the human, take no further edge —
  re-running after a fresh rebase-before-review cycle is a
  human decision in this Quest; (b) rebase conflict: abort
  the rebase, take the `block` edge with the conflicting
  files in `--reason`, never resolve silently; (c) after
  `landed`: release the quest worktree and delete the
  branch `prepare` created (`git branch -d`, never `-D`).
- Acceptance: drill (a) by moving the target between review
  and land and observing the skill stop with master at the
  moved target and no silent retry; drill (b) with a
  conflicting change and observing stage `blocked` with
  master untouched; drill (c) and observe the worktree and
  branch gone. Fails today: `release` exists but nothing
  calls it at land time, and it never deletes the branch.
- Depends on: Exp 1.

## Scorecard

Per landing: wall time ready-to-landed, rebase count, CAS
refusals absorbed, re-checks run, human interventions.
Recorded in the quest's exp records from ledger lines;
unmeasured values are stated, never zero.

## Risks and red chair

- Strongest attack on the goal: "the skill is a shell script
  wearing a costume — just teach the binary." What changed:
  conflicts and worktree ownership are judgment over another
  executor's desk; the binary stays the tiny referee (tell,
  swap, ledger). What remains open: whether tree-identical
  rebases (same tree hash, new parent) may carry verdicts
  over instead of restarting the evidence chain — deferred
  to bp3-land-verdicts with this Quest's data.
- Strongest attack on scope: a FIFO clerk for parallel
  quests. Cut: MVP lands one quest at a time by human
  decision, so ordering is designed-for but unbuilt; the
  concept is named so the follow-up inherits the word.

## Open questions

1. Does the skill land Quest branches to master directly,
   or only to the quest's integration branch with human
   promotion after? Default: existing repo rule stands —
   human promotes to master. Owner: human, at Exp 1 review.
2. Carried into bp3-land-verdicts, not answered here: the
   rebase-after-review re-entry edge, the CAS retry loop
   and its bound, tree-identical verdict carry-over, the
   landing packet, and the error envelope. This Quest's
   exp records supply the evidence (how often rebases are
   tree-identical, which refusals were hit).
