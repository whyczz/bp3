---
name: bp3g-no-human
description: Run several bp3 graphs with no human present using the bp3g conductor — fleet preflight, park blocked work in the inbox, and end with the check-in report; never attests, never pages, never promotes.
---
<!-- GENERATED from skills/bp3g-no-human/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Bp3g, no human

Use when a human in a bp3-enabled repo invokes this skill
by name (`/bp3g-no-human <graph>...`,
`$bp3g-no-human`) or asks to run graphs unattended,
overnight, or in a queue with no human present. Several
graphs may be named; a Run budget may be stated. One
output: the check-in report (step 5). For one graph with a
human present, use `bp3g` instead.

`/bp3g-no-human <graph>...` means `/bp3g <graph>` per
graph, in queue order, under the no-human rails below. Follow
the canonical `bp3g` skill (`skills/bp3g/SKILL.md`)
procedure and rules as written there — read state with
`bp3 g r`, dispatch the one step that state calls for,
re-read. This file carries no step procedure of its own,
so the two names cannot drift; it adds only the rails
that make the conductor safe with no human in the room.

## Shape

This ships as a skill mode of `bp3g`, not its own FSM.
The rails below (preflight, parking, budget, check-in report)
all state as conductor rules over the existing node FSM
without special cases: the queue is ordered iteration,
parking is stopping a graph on a `blocked` read, the
budget is a stop on dispatching, and the check-in report is
a read. No queue-level state is written anywhere; queue
words name report outcomes, never new edges.

## Fleet

Several named graphs are one fleet, not several queues.
A fleet declares its merge order before the queue starts:
the order graphs were named, unless the invoker names a
different order in the same breath. The merge order is
fixed for the whole fleet; finishing first never moves a
graph up it. Names below reuse the node's words: `fleet`,
`footprint`, `merge order`, and `check-in report`.

- Footprint: the paths a graph declares it will touch —
  every path named in its GRAPH.md Scope and in each
  node's Output. Two footprints overlap when they name
  the same path, or one names a directory the other
  names a path under. A graph with no declared footprint
  fails preflight: disjointness cannot be shown for it.
- Disjoint graphs run in parallel: each graph rides its
  own conductor loop at the same time, desks per child,
  one graph per checkout. A parked graph never holds up
  a disjoint graph; parking stops only its own graph.
- The fleet never merges: graphs ready for `goal_fin`
  are only listed, in merge order, for the owner to
  promote one at a time in that order.

## No-human rails

- Desks only: every step Run works from a prepared
  `bp3 harness desk` desk, one graph per checkout. No-human
  never works in the shared tree and never runs two
  graphs in one checkout at once.
- No-human never attests: `BP3_DECIDER` stays unset for
  the whole run, exactly as the launcher left it.
  No-human never takes `resume` or `delete`, and never
  pages a question to the owner. A decision only a human
  can make is not asked for; the work parks (below) and
  waits for morning.
- No-human never promotes or pushes: `goal_fin` stays the
  owner gate. A graph whose nodes all reach `node_fin`
  stops there; promotion waits for the owner.

## Procedure

1. Preflight each named graph before queueing it, and
   declare the merge order before the queue starts. A
   graph is not queued — and is reported with the failed
   check named — when any of these fails:
   - every node's EXPERIMENT.md carries Acceptance rows
     (an node missing Acceptance rows fails this check);
   - no EXPERIMENT.md in the graph carries an open
     design question;
   - `make check` is green (`make check` red fails
     this check);
   - the graph declares a footprint (see Fleet).
   Footprint preflight: in merge order, the first graph
   claims its footprint; a graph whose footprint overlaps
   an already-admitted graph's is refused at preflight.
   An overlapping graph is refused at preflight, named
   in the report, with zero Runs spent on it. Anything
   shared queues serially in a later fleet, never in
   parallel in this one.
   A graph that fails preflight is reported, not queued;
   the queue moves on to the next named graph.
2. Run admitted graphs in parallel, each in merge order
   for reporting. Per graph, ride the `bp3g` conductor
   loop: `needs_fix` below the cycle cap rides to the
   next cycle (Node 6 rule, no owner question); `landed`
   is reported as `node_fin` and the conductor advances
   to the next node.
3. Park, never page: when an node enters `blocked`, or
   the cycle cap is hit, park it — the node stays in the
   blocked inbox with its reason, its graph stops, and
   the fleet moves on to the other graphs. Nothing is
   resumed, deleted, or attested to unpark it.
4. Fleet budget: one budget caps the whole fleet, not
   one budget per graph. Every step Run in every graph
   counts against the one fleet budget. When the fleet
   budget is spent, every graph stops, even mid-graph.
   No new step is dispatched in any graph after the
   budget is spent, and the report says the budget stopped it.
5. Check-in report (the only output): one combined
   report for the whole fleet, from `bp3 g r`, the run
   registry, and `bp3 harness desk list` — never from
   memory or tape text:
   - graphs ready for `goal_fin`, listed in the
     predeclared merge order (fleet never merges);
   - nodes at `node_fin` (state `landed`), per graph;
   - parked items from all graphs in one check-in list,
     grouped by graph, each with its inbox reason;
   - shared-decision parks: parked items whose inbox
     reasons name the same human decision appear as one
     decision with its dependent graphs listed; owner
     words are still attested per node at resume time,
     by a human, outside the fleet;
   - refusals from preflight, each graph named with the
     failed check or the footprint it overlapped;
   - `usage_recorded` token totals summed per graph;
   - the worktree sweep result: `bp3 harness desk list`
     output, naming any desk still open.
   Then stop. Judgment waits for a human; this report
   is where the night hands over.

## Rules

- The skill writes no state. `bp3 g u` is the only
  writer, called by step children; no-human itself takes
  no verdict edge and no human edge.
- Identity rides env (`BP3_HARNESS`, `BP3_MODEL`) as in
  `bp3g`; `BP3_DECIDER` is the one env name no-human
  must never set.
- Instructions only: this skill holds no state, spawns
  no daemon, and assumes no runtime beyond the main
  session, its workflow children, and the `bp3 g`
  binary.
