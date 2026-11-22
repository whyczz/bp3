---
name: induct-inline-yolo
description: Run one bp3 quest inline with no human present — induct-inline's procedure as written, under no-human rails; park owner calls instead of paging, stop new work when a stated budget is spent, and end with the check-in report; never attests, never pages, never promotes or pushes.
---
<!-- GENERATED from skills/induct-inline-yolo/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Induct inline, no human

Use when a human in a bp3-enabled repo invokes this skill by name
(`/induct-inline-yolo <quest> [budget]`) or asks to run one quest
inline "yolo", unattended, or without stopping to ask. One quest.
One output: the check-in report (below). For one quest with a human
present, use `induct-inline`; for several quests at once, use
`induct-yolo`.

`/induct-inline-yolo <quest>` means `/induct-inline <quest>` under
the no-human rails below. Follow the `induct-inline` skill
(`skills/induct-inline/SKILL.md`) procedure and rules as written
there: author here, grade each commit with a fresh grader in the
background from the brief bp3 renders, cast at the cast boundary,
re-read. This file carries no step procedure of its own, so the two
cannot drift; it adds only the rails that make the loop safe with no
human in the room.

## No-human rails

- **Never attest**: `BP3_DECIDER` stays unset for the whole run.
  Never take `resume` or `delete`, never promote, never push:
  `goal_fin` stays the owner gate.
- **Park, never page**: where `induct-inline` would stop for the
  owner, park instead. The node stays where it is with its reason,
  and the quest's other ready nodes keep moving; parking starves
  only its dependents.

  | Situation | induct-inline | here |
  |---|---|---|
  | node `blocked` (the cycle cap, or a block) | stop, report the owed decision | park; it stays in the inbox |
  | constraints-class `needs_fix` | stop, pitch to the owner (`/teach`) | park, with the pitch written in the report |
  | scope change or acceptance-gate edit | the owner's call | park |
  | no subagent tool | the owner judges | use pi only if the invocation names it, else park at `handed_off`; never self-grade |

  Everything else is not the owner's call. Decide it, and say what
  you decided in the report: a `needs_fix` below the cap is a fix and
  a new commit, and a void verdict is the next attempt.
- **Budget**: an optional stated budget, in grades or wall minutes.
  When it is spent, start no new author step and no new grade, cast
  any finished verdicts at the next cast boundary, and stop. The
  report says the budget stopped it.
- **Grader runtime**: a fresh subagent per grade; pi only when the
  invocation names it.

## Check-in report

The only output, read from `bp3 q r <quest>`,
`bp3 q <quest> metrics r` and `bp3 harness desk list`, never from
memory:

- nodes at `node_fin`, with their rounds;
- parked nodes, each with its reason and the owner decision it waits on;
- what this run decided that was not the owner's, one line each;
- the metrics readout: `author.wall_s` and `author.active_s` per
  cycle, grade wall and `grade.tool_s`, and `brief_verbatim` /
  `brief_edited`;
- desks still open (grade desks should all be released);
- whether the quest is ready for `goal_fin`, which only the owner takes.

## Rules

- One quest per invocation and one session per quest; fleets are
  `induct-yolo`'s.
- The skill writes no state: `bp3 q` is the only writer, and every
  rule of `induct-inline` still holds.
