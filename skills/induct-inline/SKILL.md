---
name: induct-inline
description: Run one bp3 quest inside the current session with no workflow children — author each node here, have one fresh grader subagent (or the owner) judge it, cast the edges, re-read — for small quests worked hands-on.
---

# Induct inline

Use when a human in a bp3-enabled repo invokes this skill by
name (`/induct-inline <quest>`) or asks to work a quest "here",
"inline", or "without spawning workflows" in this session. One
quest. One output: the `induct` report (`node_fin`, blocked,
owed decisions), with every step done in this session except the
grade judgment.

Use `induct` to conduct with workflow children (one per ready
node, desks per node). Use `induct-yolo` when no human is
present. Use `using-bp3` for one hand-cast edge.

## How it differs from induct

| | `induct` | `induct-inline` |
|---|---|---|
| author | `node-loop` child | this session |
| grade judgment | `induct-grade` child | one fresh grader: a subagent, or a headless pi when the owner names it; without either, the owner |
| edges cast by | the looper | this session (the looper) |
| fan-out | one child per ready node | none: one node in flight |
| desk | one per node | one for the quest (self mode) |

## Procedure

1. `bp3 q r <quest>` must answer JSON, or stop. In self mode,
   prepare the quest desk exactly as `induct` step 2 does and
   work only there; host mode works in the repo.
2. Take the first node in `ready` order; its state names the step:
   - `todo`: read its NODE.md acceptance gates, make the change,
     run the gates' `prove by` checks, commit clean, then cast
     `bp3 q <quest> n <node> e handoff --commit <sha> --reason "..."`.
   - `handed_off`: grade (below).
   - `approved`: cast `e land --reason "..."`.
   - `blocked`: stop and report the owed decision.
3. Re-read after every edge. A refusal is information: re-read,
   never retry unchanged.
4. Loop until no node is ready or one blocks; give the report.

## Grade: the author never judges

This session wrote the commit, so it never forms the verdict.

- **Subagent available** (Claude Code's Agent tool, Muse's
  `agent()`): spawn one fresh grader with a cold brief — quest,
  node, the bound commit SHA, the NODE.md acceptance gates, and
  the commands to run, `make check-full` (the grade gate)
  among them; never the authoring rationale. It returns
  the verdict as data and makes no `bp3 q` calls (pure grade, as
  in `induct`). This session casts that verdict verbatim, bound to
  that SHA. One grader per grade; never reused across commits.
- **pi grader** (when the owner names pi as the grader runtime):
  run one headless pi per grade from the desk,
  `pi -p --tools read,bash --session-id <fresh id> "<cold brief>"`.
  It gets the same cold brief, whose first line names the node id
  and the commit's first 7 characters; that is how the scrape
  joins it. `--tools read,bash` keeps pi's edit and write tools
  off, and the brief still says no edits, no commits and no
  `bp3 q` calls. Check that the desk is clean before casting. One
  session per grade: a fresh `--session-id` each time, never
  reused. The verdict is the printed text, cast as returned. The
  scrape reads the session from `~/.pi/agent/sessions/` and counts
  it as `self_checked`.
- **Measure every grade.** Right after casting a verdict, run
  `bp3 q <quest> metrics scrape`. It finds the grader by the node
  id and commit SHA its brief names (spell them as `bp3 q` does),
  and the author by the handoff cast as
  `bp3 q <quest> n <node> e handoff` in one command. The scrape is
  evidence, never a gate: a `mismatched` grade is reported, and it
  never changes the verdict or blocks the land.
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

- One quest, one session, one node in flight.
- A verdict binds to the exact commit graded; a commit changed
  after the grader saw it gets a new grade.
- Clean commits only; a dirty tree is never state.
- Never attest (`BP3_DECIDER` stays unset), never `resume` or
  `delete`, never promote: `goal_fin` stays the owner gate.
- State moves only through `bp3 q`; never edit a ledger or
  `state.yaml` by hand.
