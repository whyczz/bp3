---
name: induct-inline
description: Run one bp3 quest inside the current session, the default way to run a quest — author each node here, grade each commit with one fresh grader in the background from the brief bp3 renders, cast verdicts at the cast boundary, re-read.
---

# Induct inline

Use when a human in a bp3-enabled repo invokes this skill by
name (`/induct-inline <quest>`) or asks to run, induct or work a
quest "here", "inline", or "without spawning workflows". This is
the default way to run a quest. One quest. One output: the
`induct` report (`node_fin`, blocked, owed decisions), with every
step done in this session except the grade judgment.

Use `induct` when many independent nodes should run at once with
workflow children (one per ready node, desks per node). Use
`induct-inline-yolo` to run one quest this way with no human
present, and `induct-yolo` for several. Use `using-bp3` for one
hand-cast edge.

## How it differs from induct

| | `induct` | `induct-inline` |
|---|---|---|
| author | `node-loop` child | this session |
| grade judgment | `induct-grade` child | one fresh grader: a subagent, or a headless pi when the owner names it; without either, the owner |
| edges cast by | the looper | this session (the looper) |
| fan-out | one child per ready node | one node being authored; its grades run in the background while the next ready node is authored |
| desk | one per node | one for the quest, plus one grade desk per grade |

## Procedure

1. `bp3 q r <quest>` must answer JSON, or stop. In self mode,
   prepare the quest desk exactly as `induct` step 2 does and
   author only there; host mode works in the repo. One session
   per quest: this session runs this quest and no other, and
   NODE.md build notes carry what a compaction would lose.
2. On every read, in this order:
   - each `handed_off` node with no grader for its current attempt
     (running, or finished with its verdict not yet cast): start one
     in the background (Grade, below);
   - when nothing is being authored, take the first `todo` node in
     `ready` order. Read its NODE.md acceptance gates, make the
     change, run the gates' `prove by` checks, and commit clean.
     Then cast `bp3 q <quest> n <node> e handoff --commit <sha>
     --reason "..."`, with the quest and node spelled out (or set
     as variables in the same command), so the scrape finds the
     author's window;
   - at the **cast boundary** (right after that handoff, or when
     nothing is left to author), cast each finished verdict in
     handoff order (below), land each `approved` node with
     `e land --reason "..."`, and release its grade desk;
   - `blocked`: stop and report the owed decision.
   Wait for a grader only when nothing is left to author.
3. Re-read after every edge. A refusal is information: re-read,
   never retry unchanged.
4. Loop until no node is ready and no grader is running, or one
   blocks; give the report.

`ready` already means every dependency has landed, so a node
authored while another is graded never depends on it. Casting
only at the cast boundary keeps every author window holding one
node's work: a window runs from the quest's latest edge to the
handoff, so a cast in the middle of authoring would cut it short.

## Grade: the author never judges

This session wrote the commit, so it never forms the verdict, and
it never words the grader's brief either.

- **Grade desk**: each grade runs in its own detached checkout at
  the bound commit, never in the author's desk:
  `bp3 harness desk prepare <quest> <node> --run grade-<node>-c<cycle>-a<attempt> --commit <sha>`.
  Attempts count from `a1`; a grade dispatched again gets the next
  attempt, so it never inherits a leftover desk.
- **The brief is bp3's**: render it with
  `bp3 q <quest> n <node> brief --desk <grade desk path>` and pass
  its `brief` text verbatim, adding nothing and leaving nothing
  out. The scrape renders it again and counts any difference as
  `brief_edited`. The brief carries the join line, the NODE.md
  acceptance gates, the previous round's commit and diff range,
  and `GRADING.md`, which names the grade gate (`make check-full`
  in this repo); no author rationale.
- **Subagent available** (Claude Code's Agent tool, Muse's
  `agent()`): spawn one fresh grader in the background with that
  brief as its whole prompt. It returns the verdict as data and
  makes no `bp3 q` calls (pure grade, as in `induct`). One grader
  per grade; never reused across commits.
- **pi grader** (when the owner names pi as the grader runtime):
  run one headless pi per grade from the grade desk,
  `pi -p --tools read,bash --session-id <fresh id> "<cold brief>"`.
  The cold brief is the rendered brief, whose first line names the node id
  and the commit's first 7 characters; that is how the scrape
  joins it. `--tools read,bash` keeps pi's edit and write tools
  off, and the brief still says no edits, no commits and no
  `bp3 q` calls. One
  session per grade: a fresh `--session-id` each time, never
  reused. The verdict is the printed text, cast as returned. The
  scrape reads the session from `~/.pi/agent/sessions/` and counts
  it as `self_checked`.
- **Verify, then cast**: before casting a verdict, check its grade
  desk. `git rev-parse HEAD` must print the bound commit, and
  `git status --short` must print nothing. Then cast the verdict
  verbatim, bound to that commit, and release the desk. Otherwise
  the verdict is void: cast nothing, keep the desk for the owner,
  and start the next attempt in a fresh desk.
- **Measure every grade.** Right after casting a verdict, run
  `bp3 q <quest> metrics scrape`. It finds the grader by the brief's
  first line, and each author window by its handoff cast. It writes
  wall, active and tool seconds for authors, and wall and tool
  seconds for graders, and counts `brief_verbatim` or
  `brief_edited`. The scrape is
  evidence, never a gate: a `mismatched` grade is reported, and so
  is an edited brief; neither changes the verdict or blocks the land.
- **No subagent tool**: stop at `handed_off` and show the owner
  the commit, the gate output, and the diff stat; the owner
  judges, this session casts.
- `needs_fix` below the cycle cap is weather: fix here, commit,
  hand off again, fresh grader.
- **Constraints are the owner's.** The grader brief names
  `CONSTRAINTS.md`. A commit that adds a language, library
  or surface outside it is `needs_fix`, **owner class**: never
  a mechanical fix. This session does not fix it; it stops and
  pitches the addition to the owner (`/teach`), and
  `induct-yolo` parks it. A diff to `CONSTRAINTS.md` without a
  new dated **owner-words row** in its Sign-off log is
  `needs_fix`.

## Rules

- One quest per session; one node being authored at a time;
  grades may run in the background, each in its own grade desk.
- A verdict binds to the exact commit graded; a commit changed
  after the grader saw it gets a new grade.
- Clean commits only; a dirty tree is never state.
- Never attest (`BP3_DECIDER` stays unset), never `resume` or
  `delete`, never promote: `goal_fin` stays the owner gate.
- State moves only through `bp3 q`; never edit a ledger or
  `state.yaml` by hand.
