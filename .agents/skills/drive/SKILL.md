---
name: drive
description: Drive one bp3 quest along its railway from the main session — dispatch Runs edge by edge through bp3 q until the quest is terminal or a human decision is owed.
---
<!-- GENERATED from skills/drive/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->

# Drive

Use when a human in a bp3-enabled repo invokes this skill by
name (`/drive <quest>`, `$drive <quest>`) or asks to "drive",
"run", or "keep going on" a named quest until it lands or
blocks. One quest per drive. One output: Runs dispatched
through `bp3 q`, ending in a drive report — what landed, what
is blocked, and what human decision is owed next.

Use `quest` instead to frame a new quest. Use `using-bp3`
instead for a single state operation by hand (one submit, one
review, recovery after a dead session). Use
`quest-landing-demo` instead when the quest is done and the
human wants the landing writeup. A design under review is
`red-ink`'s job, not a drive.

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
5. Otherwise take the next landable exp. Dispatch one fresh
   Run per edge through the engine's workflow: an author Run
   commits work and `submit`s the exact commit; review and
   check Runs judge that exact commit and may run in parallel;
   at `approved`, autoland with `land`. Every state move goes
   through `bp3 q <quest> u <exp> <edge>` — no exceptions.
6. Re-read after every dispatch (`bp3 q r <quest>`). A
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
