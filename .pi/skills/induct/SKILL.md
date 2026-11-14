---
name: induct
description: Induct one bp3 quest along its railway from the main session — loop the railway with induct-exp workflows until the quest is terminal or a human decision is owed.
---
<!-- GENERATED from skills/induct/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Induct

Use when a human in a bp3-enabled repo invokes this skill by
name (`/induct <quest>`, `$induct <quest>`) or asks to "induct",
"run", or "keep going on" a named quest until it lands or
blocks. One quest per induct. One output: Runs dispatched
through `bp3 q`, ending in an induct report — what landed, what
is blocked, and what human decision is owed next.

Use `quest` instead to frame a new quest. Use `using-bp3`
instead for a single state operation by hand (one submit, one
review, recovery after a dead session). Use
`red-ink-quest-landing-demo` instead when the quest is done and the
human wants the landing writeup. A design under review is
`red-ink`'s job, not an induct.

## Procedure

1. Take exactly one argument: the quest. Confirm the engine
   exists: `bp3 q r <quest>` must answer JSON. If `bp3 q` is
   unavailable, stop and say so — never improvise state with
   file edits or another command.
2. Read the world live: `bp3 q r <quest>` gives exp states,
   the railway order, and the blocked inbox. Trust only this
   read — never session memory, `state.yaml`, or a ledger read
   by hand.
3. Work the inbox first. For each blocked exp, present the
   facts in the main session (exp, reason, checkpoint, cycle),
   capture the human's decision in their words, attest it
   (`BP3_DECIDER=human`), and take `resume` or `delete`
   through `bp3 q <quest> u <exp>`. The human never calls bp3
   and never supplies a commit. Dispatch a fresh Run after a
   resume; a blocked Run is never resumed in place.
4. At a fan-out group, stop and ask the human which members
   run. Members are exploration only and never landable; when
   they settle, ask which result feeds the follow-up exp.
5. Otherwise take the next landable exp and launch the
   `induct-exp` workflow for that exp (installed with this
   skill by `bp3 skills install`; if it is missing, stop and
   say so rather than improvising children). Pass the workflow
   args `{quest, exp, ts, harness, model}`: `ts` is a UTC
   compact timestamp (for example `20261107T143022Z`) supplied
   by this skill in args because workflow scripts cannot read
   the clock, and children embed it in every run-id; `harness`
   and `model` carry this session's identity (`muse-code` and
   its model), because workflow children do not inherit the
   launching session's env and would otherwise record
   `unknown`. Children load role skills themselves: the author
   child loads `code-writer`, the review child loads
   `code-reviewer` (its `fix_first` becomes `needs_fix`), and
   the check child judges in the `verify` stance. It loops the exp's
   inner FSM — one fresh child Run per edge, review and
   check in parallel on the exact commit in `submitted`,
   autoland at `approved` — until the exp exits `landed`,
   `blocked`, or `deleted`, or a step changes nothing
   (refusals, no commit) and it returns `refused` to this
   skill for re-judging. It never loops on an unchanged state.
   The skill itself never dispatches edges one by one. Every
   state move goes through `bp3 q <quest> u <exp> <edge>` —
   no exceptions.
6. Re-read after every workflow return (`bp3 q r <quest>`). A
   refusal is information, not failure: read its error code,
   facts, and guidance, pick a legal edge, continue. Never
   retry an edge unchanged against a moved tip; re-judge from
   the fresh read.
7. Stop when the rollup is terminal (every exp `landed` or
   `deleted`) or a human decision is owed that this session
   cannot get. Report: edges taken per exp with their ledger
   evidence, Runs and tapes left behind, scorecard fields
   (wall time, context tokens, human-active minutes — or
   "unmeasured", never zero), and the next decision owed.

## Rules

- The skill writes no state. `bp3 q u` is the only writer;
  ledger files, `state.yaml`, and branch tips are never
  hand-edited, and tape is evidence, never parsed into facts.
- Human attestation comes only from actual human words in
  this session. The engine never attests on the human's
  behalf, and `resume` without it is refused
  (`E_HUMAN_REQUIRED`) — that refusal is the gate working.
- Identity rides env (`BP3_HARNESS`, `BP3_MODEL`) set per Run
  by the launcher or hooks. Unset means `unknown` plus a
  warning in the verdict; never guess a model name.
- Verdicts bind the exact commit reviewed. A verdict naming a
  superseded commit is refused; dispatch a fresh Run against
  the current commit instead of arguing with the refusal.
- Instructions only: this skill holds no state, spawns no
  daemon, and assumes no runtime beyond the main session, its
  workflow children, and the `bp3 q` binary.
