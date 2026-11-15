---
name: induct-solo
description: Run several bp3 quests unattended with the induct conductor — preflight, queue, park blocked work in the inbox, and end with the dawn report; never attests, never pages, never promotes.
---
<!-- GENERATED from skills/induct-solo/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# Induct solo

Use when a human in a bp3-enabled repo invokes this skill
by name (`/induct-solo <quest>...`, `$induct-solo`) or asks
to run quests unattended, overnight, or in a queue with no
human present. Several quests may be named; a Run budget
may be stated. One output: the dawn report (step 5). For
one quest with a human present, use `induct` instead.

`/induct-solo <quest>...` means `/induct <quest>` per
quest, in queue order, under the solo rails below. Follow
the canonical `induct` skill (`skills/induct/SKILL.md`)
procedure and rules as written there — read state with
`bp3 q r`, dispatch the one step that state calls for,
re-read. This file carries no step procedure of its own,
so the two names cannot drift; it adds only the rails
that make the conductor safe with no human in the room.

## Solo rails

- Desks only: every step Run works from a prepared
  `bp3 worktree` desk, one quest per checkout. Solo never
  works in the shared tree and never runs two quests in
  one checkout at once.
- Solo never attests: `BP3_DECIDER` stays unset for the
  whole run, exactly as the launcher left it. Solo
  never takes `resume` or `delete`, and never pages a
  question to the owner. A decision only a human can
  make is not asked for; the work parks (below) and
  waits for morning.
- Solo never promotes or pushes: `quest_fin` stays the
  owner gate. A quest whose exps all reach `exp_fin`
  stops there; promotion waits for the owner.

## Procedure

1. Preflight each named quest before queueing it. A
   quest is not queued — and is reported with the failed
   check named — when any of these fails:
   - every exp's EXPERIMENT.md carries Acceptance rows
     (an exp missing Acceptance rows fails this check);
   - no EXPERIMENT.md in the quest carries an open
     design question;
   - `make check` is green (`make check` red fails
     this check).
   A quest that fails preflight is reported, not queued;
   the queue moves on to the next named quest.
2. Run the queue in the order named. Per quest, ride
   the `induct` conductor loop: `needs_fix` below the
   cycle cap rides to the next cycle (Exp 6 rule, no
   owner question); `landed` is reported as `exp_fin`
   and the conductor advances to the next exp.
3. Park, never page: when an exp enters `blocked`, or
   the cycle cap is hit, park it — the exp stays in the
   blocked inbox with its reason, its quest stops, and
   the queue moves on to the next quest. Nothing is
   resumed, deleted, or attested to unpark it.
4. Budget: when the stated Run budget is spent, the
   queue stops, even mid-quest. No new step is
   dispatched after the budget is spent, and the dawn
   report says the budget stopped it.
5. Dawn report (the only output): per quest, from
   `bp3 q r`, the run registry, and `bp3 worktree list`
   — never from memory or tape text:
   - exps at `exp_fin` (state `landed`);
   - parked inbox items with their reasons;
   - `usage_recorded` token totals summed per quest;
   - the worktree sweep result: `bp3 worktree list`
     output, naming any desk still open.
   Then stop. Judgment waits for a human; this report
   is where the night hands over.

## Rules

- The skill writes no state. `bp3 q u` is the only
  writer, called by step children; solo itself takes
  no verdict edge and no human edge.
- Identity rides env (`BP3_HARNESS`, `BP3_MODEL`) as in
  `induct`; `BP3_DECIDER` is the one env name solo must
  never set.
- Instructions only: this skill holds no state, spawns
  no daemon, and assumes no runtime beyond the main
  session, its workflow children, and the `bp3 q`
  binary.
