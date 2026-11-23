---
status: active
home_repo: bp3
date: 2026-11-22
---

# induct-inline-as-default-measure-author: one author, background graders, measured

TL;DR
induct-inline becomes the default way to run a quest. This session
authors every node, and each grade runs as a fresh subagent in the
background while the author takes the next ready node. bp3 renders the
grader's brief, so the author can't steer it, and the scrape reports any
grade whose brief was edited. The scrape also measures author time:
`author.wall_s`, `author.active_s` (the time the casting session was
present, skipping gaps that start at an `end_turn`), and `tool_s` for authors and graders. A new
skill, induct-inline-yolo, runs one quest inline under induct-yolo's
no-human rails. The one decision: a finished background verdict is cast
only at a **cast boundary** (right after the author's next handoff, or
when nothing is left to author). That keeps every author window holding
one node's work, so the existing window rule stays exact.

ELI5
One worker writes each piece, and a fresh checker grades it. Today the
worker sits idle while the checker works. After this quest the worker
starts the next piece while the checker reads the last one. bp3 writes
the checker's instructions itself, so the worker can't nudge the
checker, and bp3 starts timing the worker as well as the checker.

## Context

Owner, 2026-11-22, after the iteration-time readout: "what if we make
induct-inline the default way, and have graders as subagents?", then
"and can we measure author time?", then "lets do both, in one quest ->
induct-inline-as-default-measure-author. and also i want a
induct-inline-yolo skill as well".

Ground, read this session:

| Fact | Source |
|---|---|
| 20 grades measured across 3 quests, all inline-shaped: author `run claude:56a60050…` (the main session), grader a subagent or `pi -p` | `bp3 q <q> metrics r`, metric-collectors, metric-followups, pi-metrics |
| grade wall median 201 s (Claude, metric-followups), 109 s (pi, pi-metrics) | same |
| inside a grade, tool time is 5–53 s of 76–237 s (Claude) and about 38 s of 86–150 s (pi); the rest is model turns | grader transcripts, tool_use → tool_result stamps, this session |
| author ≈ 53% (metric-followups, ~23 of ~44 min) and ≈ 62% (pi-metrics, ~13 of ~20 min) of quest wall, estimated from ledger dwell | `bp3 q r` timing (`wait_s`, `dwell_s`) |
| the first cycle's author time is folded into `wait_s`, which also counts waiting on other nodes; author samples carry tokens and tool calls only | `metrics r`: author keys `model, run, tokens_*, tool_calls` |
| `Metrics.author_spans` already defines each window: the quest's latest edge before the handoff (resume excluded) to the handoff | `src/quest/metrics.ml:164` |
| `Claude_tx.author_cost` builds its record with empty `first_ts`/`last_ts`, so the window's wall is dropped | `src/quest/claude_tx.ml:395` |
| `parse_session` reads assistant lines and handed_off results only; assistant lines carry `stop_reason` (`end_turn` 256, `tool_use` 4508 in this session) | `src/quest/claude_tx.ml`, this session's transcript |
| a detached checkout at a commit already exists: `bp3 harness worktree prepare <quest> <node> --run <id> --commit <sha>` | `src/quest/worktree.ml:279` |
| land merges (merge-tree) when the quest tip isn't an ancestor of the node tip | `src/quest/main.ml:280-322` |
| `bp3 q <q> n <n> brief` refuses today (`E_USAGE`) | observed |
| the hand-written cold briefs: header line naming node id and sha7, hard rules, desk, read-first list, gate, judge list, verdict shape | pi-metrics skills.1 grade session |
| `CORE_SKILLS` in `bin/bp3:36` lists the installed core skills; no induct-inline-yolo | `bin/bp3` |

Related, not promoted: `docs/icebox/2026-11-19-fast-grader.md` (author
self-mutation, delta brief with a cap, lane-sized grading). This quest
takes none of its decisions. The brief's previous-round section only
shows facts the ledger already holds (Open question 2).

## Terms

| Term | Meaning |
|---|---|
| conductor | the session running a quest; in induct-inline it also authors |
| background grade | a grader started right after a handoff, running while the conductor authors the next ready node |
| grade desk | a detached worktree at the graded commit, `bp3 harness desk prepare <quest> <node> --run grade-<node>-c<cycle>-a<attempt> --commit <sha>`; its verdict is cast only if the desk is clean at the bound commit; released after the cast |
| cast boundary | the only points where a finished background verdict is cast: right after the conductor's next handoff, or when nothing is left to author |
| grade brief | the text `bp3 q <quest> n <node> brief` renders for a handed-off node: join line, rules, read-first list, the NODE.md Acceptance gates verbatim, the previous round (commit and diff range, never its `--reason`), GRADING.md, the verdict shape |
| `Brief.render` | the pure function behind the verb; the scrape calls it again to check a grade's first prompt |
| `Brief.inputs` | the one function that gathers render's inputs (cycle, previous `needs_fix` commit, other nodes' commits) as of a handoff stamp; the verb and the scrape both call it |
| `GRADING.md` | new root doc: the repo's grade gate and grader rules, appended verbatim to every brief |
| `Names` | new `src/quest/names.ml`: one constant per CLI verb, flag and error code this quest adds; a rename edits this file and seds the skills (red-ink round 6). Metric and tally names keep their one home in `Metrics`. Everything else: `docs/icebox/2026-11-22-names-constants.md` |
| author window | unchanged: `Metrics.author_span`, from the quest's latest edge before the handoff (resume excluded) to the handoff |
| `author.wall_s` | the window's span in seconds (ledger stamps) |
| `author.active_s` | the time the casting session was present in the window: the sum of gaps between its consecutive main-thread lines, skipping any gap that starts at an assistant line with `stop_reason` `end_turn`; the span before its first line in the window is never active |
| `author.tool_s`, `grade.tool_s` | the union of `[tool_use stamp, tool_result stamp]` intervals, inside the active gaps; parallel calls count once |
| `brief_verbatim`, `brief_edited` | scrape tally counts: grades whose first prompt equals `Brief.render` for that handoff (the `Desk:` line aside), or doesn't |
| induct-inline-yolo | new skill: induct-inline's procedure as written, plus no-human rails (never attest, never resume or delete, never promote or push, park instead of paging, optional budget, check-in report) |

## Inputs

| Input | Source |
|---|---|
| the quest ledger, node ledgers | as today |
| Claude Code main session and subagent transcripts | as today; `parse_session` also reads `tool_result` stamps and `end_turn` stamps |
| pi sessions | as today; `toolResult` stamps |
| `docs/quests/<q>/nodes/<n>/NODE.md`, `GRADING.md`, `QUEST.md` at the bound commit | read by `Brief.render` via git, never from the working tree |
| `--desk <path>` | optional on `brief`: adds one `Desk:` line; an absolute path to an existing directory, one line, else `E_USAGE`. The only caller input that reaches the brief |

## Outputs

| Output | Shape |
|---|---|
| `bp3 q <q> n <n> brief [--desk <path>]` | `{"ok":true,"quest","node","cycle","commit","brief"}`; refuses outside `handed_off` with `E_NOT_HANDED_OFF` (facts `state`, `legal_edges`) |
| new metrics | `author.wall_s`, `author.active_s`, `author.tool_s` (owner `author-window`), `grade.tool_s` (owner `grade-transcripts`); unit `s`, agg `Sum` |
| `metrics r` rollup | gains `author_wall_s` and `author_active_s` stats beside `grade_wall_s` |
| scrape JSON | per-node tally gains `brief_verbatim`, `brief_edited`; not outcome buckets, so `buckets_add_up` is unchanged |
| skills | induct-inline as the default (background grades, grade desks, cast boundary, rendered brief, one session per quest); using-bp3 and induct point to it; new `skills/induct-inline-yolo/SKILL.md`, in `CORE_SKILLS` |
| `GRADING.md` | new root doc (gate `make check-full`, the repo's grader rules) |

## Acceptance gates (observed today, then design trace)

Observed 2026-11-22:

```text
$ bp3 q 2026-11-21-pi-metrics metrics r | jq -c '.nodes["node-reader-1-pi-session"].cycles["1"].author | keys'
["model","run","tokens_cache_read","tokens_cache_write","tokens_in","tokens_out","tool_calls"]
$ bp3 q 2026-11-21-pi-metrics n node-reader-1-pi-session brief
{"ok":false,"error":{"code":"E_USAGE",...}}
$ ls skills/induct-inline-yolo
ls: skills/induct-inline-yolo: No such file or directory
```

Design trace, after the quest:

```text
measure.1  unit: window 460 s, one 300 s gap after an end_turn, tools 30 s + 30 s (one call parallel inside another)
           -> author.wall_s 460, author.active_s 155, author.tool_s 60; the same lines in a window opened 2 h early -> active 155
           metrics.sh: a fixture session -> 3 author.* time samples; a grader -> grade.tool_s
brief.1    bp3 q q1 n nd brief --desk /d -> first line "Grade nd at abc1234 (full SHA …) in quest q1, cycle 1.",
           the NODE.md Acceptance gates verbatim, GRADING.md verbatim, "Desk: /d"; cycle 2 adds the
           previous commit and `git diff <prev7>..<sha7>` (never the reason); todo -> E_NOT_HANDED_OFF
brief.2    metrics.sh: a grader whose first prompt is the render -> brief_verbatim 1;
           one extra line -> brief_edited 1, the grade still written
skills.1   induct-inline: background grade in a grade desk, cast boundary, rendered brief, one session per quest;
           g.sh: B committed on top of A in one desk, land A then B -> both landed, desk clean
skills.2   skills/induct-inline-yolo/SKILL.md and every render; in CORE_SKILLS; rails present; no step procedure of its own
probe      before brief.1's handoff, in a scratch clone: commits A, B stacked in one desk; land A, land B -> both landed, desk clean
dogfood    bp3 q 2026-11-22-induct-inline-as-default-measure-author metrics r -> author.wall_s and
           author.active_s for every cycle; brief_verbatim for every grade cast after brief.1;
           measure.1 and brief.1 overlapped (one graded in the background while the other was authored)
all        make check-full rc 0
```

## Goal and why

Make the measured way the default way, and measure the half that isn't
measured yet. The author is more than half of quest wall and today has
no wall number, so it can't be pushed down. The grader's wall is the
author's dead time, and overlapping the two is the cheapest saving
there is.

## Success picture

`metrics r` for this quest shows `author.wall_s` and `author.active_s`
for every cycle and `brief_verbatim` for every grade from brief.1 on.
At least one grade ran in the background while another node was being
authored, and both landed. A fresh session can run
`/induct-inline-yolo <quest>` from the skill text alone.

## Scope

| In | Out |
|---|---|
| author wall, active and tool time; grade tool time (measure.1) | a time cap or delta-only grading (fast-grader icebox, Open question 2) |
| `brief` verb, `Brief.render`, `GRADING.md` (brief.1) | changing who may land, attest or promote |
| brief check in the scrape (brief.2) | blocking on `brief_edited`: evidence only, like the scrape (Open question 3) |
| induct-inline as default, background grades, grade desks, cast boundary (skills.1) | deleting `induct` or its workflow steps (Open question 1) |
| induct-inline-yolo skill (skills.2) | fleets in induct-inline-yolo: one quest per invocation; fleets stay induct-yolo's |
| | pi author windows (pi-metrics Open question 1) |

## Constraints at approval

Constraints pass: none. The code is OCaml with yojson and str. The
verb rides the `bp3 q` door (the bp3 CLI surface). The new skill is
markdown in the skills surface, and `GRADING.md` is a doc.
`bin/bp3`'s `CORE_SKILLS` edit is bash, already signed.

Common-sense pass (CONTEXT.md, claims checked 2026-11-19/20, inside 90
days):

- One writer per node, parallel only across independent nodes
  (CONTEXT.md:22). Background grades keep one author; only graders
  overlap, and only for nodes `ready` lists.
- A worktree per agent or task is mainstream isolation
  (CONTEXT.md:39). Each grader gets its own grade desk.
- Reviewers aren't told who wrote the code (CONTEXT.md:104). The
  rendered brief carries no author rationale, by construction.
- Judges favor their own outputs (CONTEXT.md:93). The author still
  never judges.
- Where we differ: later rounds still re-grade in full (CONTEXT.md:99).
  The brief shows the previous round, but this quest adds no delta-only
  rule.

## Human touchpoints

| When | Owner |
|---|---|
| approval of this frame | owner |
| each grade | a fresh Claude Code subagent per commit, cast as returned (owner: "have graders as subagents") |
| promotion | owner |

## Nodes

### Milestone: measure

| Node | TL;DR |
|---|---|
| [measure.1 - author-time](nodes/node-measure-1-author-time/NODE.md) | the scrape writes `author.wall_s`, `author.active_s`, `author.tool_s` and `grade.tool_s` |

### Milestone: brief

| Node | TL;DR |
|---|---|
| [brief.1 - grade-brief](nodes/node-brief-1-grade-brief/NODE.md) | `bp3 q <q> n <n> brief` renders the cold brief from the bound commit; `GRADING.md` holds the repo's gate and rules |
| [brief.2 - brief-check](nodes/node-brief-2-brief-check/NODE.md) | the scrape re-renders each grade's brief and counts `brief_verbatim` or `brief_edited` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - inline-default](nodes/node-skills-1-inline-default/NODE.md) | induct-inline is the default conductor, with background grades in grade desks and a cast boundary (skill node) |
| [skills.2 - inline-yolo](nodes/node-skills-2-inline-yolo/NODE.md) | new skill induct-inline-yolo: induct-inline under no-human rails (skill node) |

## Scorecard

From `metrics r` for this quest: `author.wall_s`, `author.active_s` and
`author.tool_s` per cycle, and grade wall and `grade.tool_s` per grade.
Quest wall per node is compared with metric-followups (~11 min) and
pi-metrics (~7 min). The time the overlap saved is the grade wall that
ran while another node was being authored, from the ledger stamps.

## Risks and red chair

Strongest attack (engineering): "background grades on one desk mix
nodes. The next node's commit sits on top of the graded one, a
`needs_fix` puts its fix on top of another node's commit, and a grader
in the shared desk watches files change under it." Settled in the
design:

- each grader works in a grade desk, a detached checkout at its commit,
  never in the author's desk;
- the cast boundary means the desk is clean whenever a verdict is cast
  or a node lands (a handoff needs a clean tree);
- the cycle-2 brief lists the other nodes' commits inside
  `<prev>..<sha>`;
- land already merges when the quest tip isn't an ancestor.

What stays untested is a merge-land while the branch is checked out in
a desk. The first stacked land in this quest is measure.1's, cast right
after brief.1's handoff. So before brief.1's handoff, the conductor
probes the exact sequence in a scratch clone: two commits stacked in one
desk, land A, land B, desk clean. The result goes in this file's build
notes (red-ink round 4, owner: "A"). If the probe breaks, handoffs go
serial and a fix node is appended. skills.1's g.sh fixture stays as the
regression test.

Second attack (independence): "the author still pastes the brief and can
edit it." Settled by brief.2: the scrape re-renders the brief and counts
`brief_edited`.

Third attack (measurement): "`active_s` calls anything after an
`end_turn` idle, including the wait for a background grader." That is
intended: nothing is being authored then. The response latency after a
human prompt also counts as idle, a few seconds per human turn. This is
an undercount, and measure.1's notes say so.

Fourth attack (context): "one author for a whole quest bloats one
session; this one already compacted." The design doesn't settle this.
The rule is one session per quest, with NODE build notes carrying state
across a compaction. The scorecard tracks author cache reads per node.

Attack on the source (the owner's prompt): "making inline the default
throws away induct's fan-out." Answered with evidence: zero measured
workflow-mode runs. `induct` stays, named as the mode for quests with
many independent nodes. Background grades recover the overlap that
matters, since grade wall is the author's dead time. "induct-inline-yolo
duplicates induct-yolo": it carries rails only and follows induct-inline
as written, as induct-yolo does with induct. skills.2 tests that it has
no numbered procedure of its own.

## Open questions

1. Retire `induct`'s workflow path (node-loop, induct-grade,
   induct-node) once no quest has picked it for a while? Owner, after
   this quest's scorecard.
2. Promote the fast-grader icebox (self-mutation, delta brief with a
   cap, lane-sized grading) as the next quest, now that author and tool
   time are measured? Owner.
3. Should `brief_edited` ever block a land, or stay evidence? Owner,
   after the first real `brief_edited`.

## Node diagram

```text
measure.1 ─────────┐
 (author time)     ├──> brief.2 ──> skills.1 ──> skills.2
brief.1 ───────────┘   (check)     (default)    (inline-yolo)
 (grade brief)
measure.1 and brief.1 share no file: one is graded in the background while the other is authored
probe (scratch clone, stacked land) runs before brief.1's handoff, the quest's first stacked land
```

## Decision record (red-ink, 2026-11-22)

| Round | Slice | Decision (owner's words) | Before -> after |
|---|---|---|---|
| 1 | Output | "A" | grader gate and rules live in a root `GRADING.md`, appended verbatim to every brief and read at the bound commit; editing it in a commit is owner-class (kept as written) |
| 2 | Inputs | "A" | no text the author typed reaches the grader: the cycle-2 brief drops the ledger `--reason` (commit and diff range only, full re-grade); `--desk` must be an absolute existing dir on one line, else `E_USAGE` |
| 3 | Data | "A" | `author.active_s` counts only the casting session's presence: gaps between its consecutive lines in the window, skipping gaps that start at `end_turn`; the span before its first line is wall, never active |
| 4 | State | "A" | before the first stacked land (brief.1's handoff), probe two stacked commits landing in a scratch-clone desk; record it in QUEST build notes; if it breaks, serial handoffs and a fix node; the g.sh fixture stays in skills.1 as the regression test |
| 5 | Functions | "A" | verify, then cast: a background verdict is cast only if its grade desk is at the bound commit and clean; otherwise void, the desk kept, a fresh grader in a fresh desk `grade-<node>-c<cycle>-a<attempt>`. Also, no question: `Brief.inputs` is shared by the verb and the scrape |
| 6a | Names | "constants in the BP3 binary, the skills stay where they are, if we need to rename, we can rename the skills (e.g. sed) and change the contants file" | new `src/quest/names.ml` (brief.1) holds this quest's new spellings; skills stay plain words; existing verbs move later (icebox `2026-11-22-names-constants.md`); `brief` joins `Store.reserved_slugs` |
| 6b | Names | "A (recommended): coin E_NOT_HANDED_OFF, with facts {state, legal_edges}" | `brief` outside `handed_off` refuses `E_NOT_HANDED_OFF` {state, legal_edges}, a `Names` constant; was `E_ILLEGAL_EDGE` with `edge: brief` |
| 7 | Concepts | "A" | three coined concepts survive: background grade, grade desk, cast boundary; "idle gap" dropped, `author.active_s` defined directly |

Closing red chair (settled copy, 2026-11-22): ship. Major, settled by
acceptance: the conductor copies a brief of several KB into the Agent
prompt, and a slip would read as `brief_edited`. The harness stores
prompts exactly (checked on 2 subagent transcripts); brief.2's done-when
needs this quest's own grades to read `brief_verbatim`; pi briefs pass
through `$(…)` exactly. Minor, open: the cast boundary is a skill rule
only, and a breach undercounts author time silently. Minor: the cost of
widening `parse_session` is measured in measure.1's build notes.
Constraints pass: none. Common-sense pass: matches CONTEXT.md:22, :39,
:93, :104; differs from :99 by choice (round 2). Adopted by the owner:
"i like this, settle'd let's adopt this".

## Build notes (2026-11-22)

Stacked-land probe (red-ink round 4), run before measure.1's handoff,
the quest's first stacked land. brief.1 went first in `ready` order. In
a scratch repo with this desk's binary
(`scratchpad/probe-stacked-land.sh`):

- commit A, handoff na; commit B on top, handoff nb;
- ship and land na, then nb: both `node_fin`;
- the desk's `git status --short` was empty after each land, and a
  commit afterwards worked.

The strongest attack's premise was wrong. `land` merges the state
branches (`bp3/quest/<q>`, `bp3/node/<q>/<n>`) and never moves the
desk's code branch `quest/<q>`. Stacked commits therefore can't disturb
the desk. Background grades with stacked handoffs stand.
