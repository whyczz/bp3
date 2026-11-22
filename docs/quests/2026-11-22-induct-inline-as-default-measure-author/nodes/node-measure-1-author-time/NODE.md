---
date: 2026-11-22
quest: ../../QUEST.md
node: measure.1
status: proposed
---

# measure.1 - author-time: the scrape times the author

## TL;DR

The scrape already finds each author window and writes its tokens and
tool calls. It now also writes three times for the window:
`author.wall_s` (the window's span), `author.active_s` (the time the
casting session was present: the gaps between its consecutive lines in
the window, skipping any gap that starts at an assistant `end_turn`)
and `author.tool_s` (time inside tool calls). Every grade gains `grade.tool_s`, so a grade's wall
splits into tool time and model time.

## Acceptance gates

Observed today:

```text
$ bp3 q 2026-11-21-pi-metrics metrics r | jq -c '.nodes["node-reader-1-pi-session"].cycles["1"].author | keys'
["model","run","tokens_cache_read","tokens_cache_write","tokens_in","tokens_out","tool_calls"]
```

Design trace (unit, synthetic main session; window [10:00:00, 10:07:40]):

```text
10:00:00 window opens (ledger); the session's first line is 10:00:05     -> those 5 s are not active
10:00:05 assistant tool_use t1, t2 (parallel)   t2 result 10:00:20, t1 result 10:00:35   -> tools [05, 35) = 30 s
10:02:00 assistant text, stop_reason end_turn                             -> active [00:05, 02:00) = 115 s
10:07:00 assistant (answering the human)                                  -> gap [02:00, 07:00) skipped: starts at end_turn
10:07:10 assistant tool_use t3 (the handoff cast), result 10:07:40        -> active [07:00, 07:40) = 40 s; tools 30 s
Claude_tx window times -> wall 460, active 155, tool 60
same lines, window opening at 08:00:00 (a new session after a break)     -> wall 7660, active 155, tool 60
an end_turn as the window's last line                                     -> adds nothing
grader transcript: tool_use 12:00:00 -> result 12:00:36, wall 90 -> grade.tool_s 36
```

```yaml
objective: every author cycle has a wall, an active and a tool time, and every grade a tool time
prove by:
  - test/unit/test_metrics.ml cases above, plus the laws below
  - test/metrics.sh: a fixture main session -> author.wall_s, author.active_s, author.tool_s samples; a grader -> grade.tool_s
  - in a scratch clone: bp3 q 2026-11-21-pi-metrics metrics scrape -> author.wall_s near 321 / 309 / 132 (ledger dwell estimate)
  - make check-full
done when: the cases and laws pass, the fixture writes the four metrics, and the scratch scrape's walls match the ledger spans
```

## Diagram

```text
ledger edges ──> author_spans (unchanged) ──> window [from, upto]
main session ──> parse_session ──> msgs, tool_use stamps, tool_result stamps, end_turn stamps
                                        │
                     window_times ──────┴──> wall = upto - from                       (ledger)
                                             active = Σ (b - a) over consecutive lines a, b
                                                      in the window, a not an end_turn  (this session only)
                                             tool = |∪ [use, result)| inside active gaps
grader transcript ──> parse ──> grade.tool_s = |∪ [use, result)|
```

## Pseudocode

```python
def window_times(session, frm, upto):
    wall = upto - frm                                  # ledger stamps, whole seconds
    lines = session.lines_in(frm, upto)                # main thread: assistant lines and tool results, in time order
    present = [(a.ts, b.ts) for a, b in zip(lines, lines[1:]) if not a.end_turn]
    active = measure(union(present))                   # before the first line: not active (another session, a break)
    tools = [(u, r) for (u, r) in session.tool_spans_in(frm, upto) if r is not None]   # unpaired: 0 (lower bound)
    tool = measure(union(tools) & union(present))
    return wall, active, tool                         # law: 0 <= tool <= active <= wall

def grade_tool_s(tx):                                  # Claude subagent or pi session
    return measure(union([(u, r) for (u, r) in tx.tool_spans if r is not None]))
```

## Tables

| Field | Value |
|---|---|
| Intent | author time is a measured number, not a guess from dwell |
| Lane | standard |
| Output | `src/quest/claude_tx.ml` (`end_turn` and `tool_result` stamps, window times), `src/quest/pi_tx.ml` (tool spans), `src/quest/metrics.ml` (registry rows, rollup stats), `src/quest/metrics_io.ml` (write), `test/unit/test_metrics.ml`, `test/unit/test_pi_tx.ml`, `test/metrics.sh` |
| Acceptance | the four metrics exist and are written; fails today (keys above) |
| Depends on | none |
| Must not touch | `src/quest/main.ml`, `test/unit/dune`, `test/g.sh` (brief.1's files, so the two can overlap) |

| Metric | Owner | Unit | Agg |
|---|---|---|---|
| `author.wall_s` | author-window | s | Sum |
| `author.active_s` | author-window | s | Sum |
| `author.tool_s` | author-window | s | Sum |
| `grade.tool_s` | grade-transcripts | s | Sum |

| Case | Counts as |
|---|---|
| parallel tool calls | once (union of intervals) |
| a `tool_use` with no `tool_result` in the window | 0: tool time is a lower bound |
| `end_turn` as the window's last line | adds nothing |
| window opens before the casting session's first line (a new session, a break, a crash) | that span is wall, never active |
| a sidechain (subagent) line in the main file | ignored, as today |
| an author window that writes nothing today (`author_missing`, `author_bad_usage`) | writes no times either |

## Prose

The window is already right. `Metrics.author_spans` runs from the
quest's latest edge before a handoff to the handoff, so in a serial run
it holds exactly one node's authoring. skills.1's cast boundary keeps it
that way once grades run in the background. This node only stops
throwing the window's times away.

Wall comes from the ledger, not the transcript. The ledger is what the
quest actually waited on, and its stamps are whole seconds. Active and
tool time come from transcript stamps, which have milliseconds.

Active time counts only what the casting session did (red-ink round 3,
owner: "A"). A window belongs to the one session that cast its handoff,
and its tokens already come from that session alone. Active is
therefore the sum of the gaps between that session's consecutive lines
inside the window. A window that opens before the session's first line
(a new session after a break, or after a crash) keeps that span as
wall, never as active. metric-collectors' derive.1 sat in todo for
6924 s, and some of that may have been exactly this.

A gap that starts at an `end_turn` is skipped. The session had finished
its turn and was waiting, for a human or for a notification, and
nothing is authored in that time, whatever it waited for. The gap runs
to the next parsed line, so the model's first-token latency after a
human prompt is skipped too, a few seconds per human turn. That is a
stated undercount of active time.

Reading `tool_result` stamps means `parse_session` parses every user
line holding a tool result, not only handed-off ones. The build notes
record scrape wall time on this repo's largest session, before and
after.

Old quests gain the new metrics on a re-scrape: the sink's dedupe key
includes the metric name, and the transcripts are still on disk.

## Tests

Known cases: the trace above (the late-opening window included), plus
the unpaired call, the trailing `end_turn`, a pi grade's `grade.tool_s`,
and an empty window. Property-based: for generated windows, lines,
`end_turn` flags and tool spans,
`0 <= tool <= active <= wall`, and `tool` never exceeds the sum of the
call durations.

## Build notes (2026-11-22)

- `Claude_tx`:
  - spans helpers `merge`, `measure`, `inter`, `paired` and `ms`;
  - `tx.tool_spans` (each tool_use stamp to its tool_result) and
    `cost.tool_s`;
  - `session.s_marks` (main-thread assistant and tool-result lines,
    flagged when the message's `stop_reason` is `end_turn`) and
    `s_results_at`;
  - `window_times`, implementing the round-3 rule: gaps between the
    session's lines, a gap starting at an `end_turn` skipped, clipped to
    `[from, upto]`, tool time inside the present gaps.
  `parse_session` now parses every line holding a `tool_result`, not
  only handed-off ones.
- `Pi_tx`: `tx.tool_spans` (toolCall entry to toolResult entry) and
  `cost.tool_s`.
- `Metrics`: rows `grade.tool_s`, `author.wall_s`, `author.active_s`,
  `author.tool_s` (seconds, `Sum`); the rollup gains `author_wall_s` and
  `author_active_s` stats beside `grade_wall_s`.
- `Metrics_io`: grades write 8 samples (was 7) and author windows 8
  (was 5).
- Tests:
  - `test/unit/test_metrics.ml`: the trace above as a known case (460 /
    155 / 60, the late-opening window 7660 / 155 / 60, the trailing
    `end_turn` 150 / 115 / 30, t9 unpaired), grade tool time as a union
    (36 s of a 90 s wall), and a law over generated lines, turn ends and
    calls (300 runs).
  - `test/unit/test_pi_tx.ml`: `tool_s` 35.
  - `test/metrics.sh`, 65 assertions: grade `tool_s` 0.6 (one answered
    call of three); pa `tool_s` 0.3; author times present and ordered;
    the rollup stats; sample counts 7→8 and 12→16.
- Mutants, each red then restored (`cmp`):
  - gaps that start at `end_turn` counted: the trace case;
  - tool time summed, not unioned: the grade tool-time case;
  - time before the first line counted: the trace case.
- Dogfood, in a scratch clone (all `refs/heads` fetched), pi-metrics
  re-scraped with `--claude-dir ~/.claude/projects/-Users-whycz-m-bp3`
  and its pi desk dir:

  | node | author wall | active | tool | grade tool / wall |
  |---|---|---|---|---|
  | reader.1 | 321 | 315.3 | 114.7 | 37.5 / 150.6 |
  | scrape.1 | 309 | 308.4 | 114.5 | 37.1 / 109.2 |
  | skills.1 | 132 | 131.6 | 71.1 | 37.4 / 86.7 |

  The walls equal the ledger dwell estimates exactly (321 / 309 / 132).
  Active is close to wall because no human was in the loop.
- Scrape cost of the wider parse: 1.21 s before, 1.25 s after, the same
  clone and dirs (67 MB of main sessions).
- Cycle 2: the grader's two mechanical fixes, plus two fixes the
  dogfood found.
  - Grader fix 1: t9 moves to 10:07:05, outside t3's span, so a count
    of unpaired calls would show.
  - Grader fix 2: `case_author_pass_writes_the_window_times` drives
    `Metrics_io.author_pass` and asserts 460 / 155 / 60 on the scrape
    path. The metrics.sh window is 0 s wide, so it couldn't.
  - Dogfood: this quest's first two casts named the node as `n $N`, and
    both author windows read `author_missing`. `Claude_tx.casts_node` now
    accepts the node, like the quest, as a shell variable the same
    command sets.
  - Dogfood: measure.1's own grade read `ambiguous`. brief.1's cycle-2
    brief lists "954bb16 (node-measure-1-author-time)" in its previous
    round and ran inside measure.1's window. `Metrics_io.claimants`:
    when several transcripts claim a grade, the single one whose first
    line names node and commit (`Claude_tx.join_line_names`) wins. A
    lone claimant still joins anywhere in its prompt, because 8 of this
    session's 18 older hand-written briefs open with "You are a fresh…".
  - Tests: metrics.sh pd (join line beats a later mention: self_checked
    1, ambiguous 0) and pe (a lone claimant below the first line still
    joins); 67 assertions.
  - Mutants, each red then restored (`cmp`):
    - unpaired author calls counted to `upto`: the trace case;
    - author times written as 0: the author_pass case;
    - node must be literal: the casts case;
    - tie-break removed: metrics.sh pd;
    - join line read as the whole prompt: metrics.sh pd.
    A first run of the zero-times mutant didn't compile (an unused
    variable), so the run counted here is the one that does.
  - Re-scrape of this quest with the fix: brief.1 c1 author 753 s
    (active 752.8, tool 325.6), measure.1 c1 author 561 s (active 560.5,
    tool 133.7); measure.1 c1 grade checked, 633 s wall, 75 s tools.
