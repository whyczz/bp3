---
name: induct-quest-no-human
description: Run several bp3 quests with no human present using the induct conductor — fleet preflight, park blocked work in the inbox, and end with the check-in report; never attests, never pages, never promotes.
---
<!-- GENERATED from skills/induct-quest-no-human/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# Induct quest, no human

Use when a human in a bp3-enabled repo invokes this skill
by name (`/induct-quest-no-human <quest>...`,
`$induct-quest-no-human`) or asks to run quests unattended,
overnight, or in a queue with no human present. Several
quests may be named; a Run budget may be stated. One
output: the check-in report (step 5). For one quest with a
human present, use `induct` instead.

`/induct-quest-no-human <quest>...` means `/induct <quest>` per
quest, in queue order, under the no-human rails below. Follow
the canonical `induct` skill (`skills/induct/SKILL.md`)
procedure and rules as written there — read state with
`bp3 q r`, dispatch the one step that state calls for,
re-read. This file carries no step procedure of its own,
so the two names cannot drift; it adds only the rails
that make the conductor safe with no human in the room.

## Shape

This ships as a skill mode of `induct`, not its own FSM.
The rails below (preflight, parking, budget, check-in report)
all state as conductor rules over the existing exp FSM
without special cases: the queue is ordered iteration,
parking is stopping a quest on a `blocked` read, the
budget is a stop on dispatching, and the check-in report is
a read. No queue-level state is written anywhere; queue
words name report outcomes, never new edges.

## Fleet

Several named quests are one fleet, not several queues.
A fleet declares its merge order before the queue starts:
the order quests were named, unless the invoker names a
different order in the same breath. The merge order is
fixed for the whole fleet; finishing first never moves a
quest up it. Names below reuse the exp's words: `fleet`,
`footprint`, `merge order`, and `check-in report`.

- Footprint: the paths a quest declares it will touch —
  every path named in its QUEST.md Scope and in each
  exp's Output. Two footprints overlap when they name
  the same path, or one names a directory the other
  names a path under. A quest with no declared footprint
  fails preflight: disjointness cannot be shown for it.
- Disjoint quests run in parallel: each quest rides its
  own conductor loop at the same time, desks per child,
  one quest per checkout. A parked quest never holds up
  a disjoint quest; parking stops only its own quest.
- The fleet never merges: quests ready for `quest_fin`
  are only listed, in merge order, for the owner to
  promote one at a time in that order.

## No-human rails

- Desks only: every step Run works from a prepared
  `bp3 worktree` desk, one quest per checkout. No-human
  never works in the shared tree and never runs two
  quests in one checkout at once.
- No-human never attests: `BP3_DECIDER` stays unset for
  the whole run, exactly as the launcher left it.
  No-human never takes `resume` or `delete`, and never
  pages a question to the owner. A decision only a human
  can make is not asked for; the work parks (below) and
  waits for morning.
- No-human never promotes or pushes: `quest_fin` stays the
  owner gate. A quest whose exps all reach `exp_fin`
  stops there; promotion waits for the owner.

## Procedure

1. Preflight each named quest before queueing it, and
   declare the merge order before the queue starts. A
   quest is not queued — and is reported with the failed
   check named — when any of these fails:
   - every exp's EXPERIMENT.md carries Acceptance rows
     (an exp missing Acceptance rows fails this check);
   - no EXPERIMENT.md in the quest carries an open
     design question;
   - `make check` is green (`make check` red fails
     this check);
   - the quest declares a footprint (see Fleet).
   Footprint preflight: in merge order, the first quest
   claims its footprint; a quest whose footprint overlaps
   an already-admitted quest's is refused at preflight.
   An overlapping quest is refused at preflight, named
   in the report, with zero Runs spent on it. Anything
   shared queues serially in a later fleet, never in
   parallel in this one.
   A quest that fails preflight is reported, not queued;
   the queue moves on to the next named quest.
2. Run admitted quests in parallel, each in merge order
   for reporting. Per quest, ride the `induct` conductor
   loop: `needs_fix` below the cycle cap rides to the
   next cycle (Exp 6 rule, no owner question); `landed`
   is reported as `exp_fin` and the conductor advances
   to the next exp.
3. Park, never page: when an exp enters `blocked`, or
   the cycle cap is hit, park it — the exp stays in the
   blocked inbox with its reason, its quest stops, and
   the fleet moves on to the other quests. Nothing is
   resumed, deleted, or attested to unpark it.
4. Fleet budget: one budget caps the whole fleet, not
   one budget per quest. Every step Run in every quest
   counts against the one fleet budget. When the fleet
   budget is spent, every quest stops, even mid-quest.
   No new step is dispatched in any quest after the
   budget is spent, and the report says the budget stopped it.
5. Check-in report (the only output): one combined
   report for the whole fleet, from `bp3 q r`, the run
   registry, and `bp3 worktree list` — never from
   memory or tape text:
   - quests ready for `quest_fin`, listed in the
     predeclared merge order (fleet never merges);
   - exps at `exp_fin` (state `landed`), per quest;
   - parked items from all quests in one check-in list,
     grouped by quest, each with its inbox reason;
   - shared-decision parks: parked items whose inbox
     reasons name the same human decision appear as one
     decision with its dependent quests listed; owner
     words are still attested per exp at resume time,
     by a human, outside the fleet;
   - refusals from preflight, each quest named with the
     failed check or the footprint it overlapped;
   - `usage_recorded` token totals summed per quest;
   - the worktree sweep result: `bp3 worktree list`
     output, naming any desk still open.
   Then stop. Judgment waits for a human; this report
   is where the night hands over.

## Rules

- The skill writes no state. `bp3 q u` is the only
  writer, called by step children; no-human itself takes
  no verdict edge and no human edge.
- Identity rides env (`BP3_HARNESS`, `BP3_MODEL`) as in
  `induct`; `BP3_DECIDER` is the one env name no-human
  must never set.
- Instructions only: this skill holds no state, spawns
  no daemon, and assumes no runtime beyond the main
  session, its workflow children, and the `bp3 q`
  binary.
