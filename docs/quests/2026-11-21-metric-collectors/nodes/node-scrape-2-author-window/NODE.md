---
date: 2026-11-21
quest: ../../QUEST.md
node: scrape.2
status: proposed
---

# scrape.2 - author-window: what the authoring session spent per cycle

## TL;DR

For every `handoff` edge, `metrics scrape` finds the Claude Code
main session whose Bash call cast it. It sums that session's own
messages over the cycle's author window, and writes five `author.*`
samples. Subagent spend is not in the window: it is in the
subagent's own file, and grades are scrape.1's.

## Acceptance gates

Observed today: no author cost exists anywhere. `bp3 q r` has
`timing.dwell_s.todo` per node, summed over cycles, with no tokens
or tool calls.

Design trace:

```text
$ bp3 q 2026-11-19-constraints-context metrics scrape
{"ok":true,"nodes":{"node-rules-4-lint-hardening":{"handoffs":4,"author_written":20,...}}}
$ bp3 q 2026-11-19-constraints-context metrics r | jq '.nodes["node-rules-4-lint-hardening"].cycles["4"].author'
{"tool_calls":<n>,"tokens_in":<n>,"tokens_out":<n>,"tokens_cache_read":<n>,"tokens_cache_write":<n>,
 "window":["2026-11-21T20:52:01Z","2026-11-21T20:52:09Z"],"run":"claude:<session>"}
```

```yaml
objective: each cycle's authoring spend, from the session that cast its handoff, over a window that never overlaps another
prove by:
  - a fixture in test/ with one synthetic main session carrying two nodes' cycles back to back, a compaction summary line, and a subagent
  - the observed run on constraints-context on this machine
  - make check-full
done when:
  - the two nodes' windows do not overlap, and their sums are at most the session's total
  - no subagent message is counted in an author window
  - a handoff whose casting session is not on disk is counted "author_missing", never zero
  - a second scrape writes 0
```

## Diagram

```text
handoff edge (node, cycle, commit, ts)
   |
   v
session = main transcript with a Bash tool_use whose command has "handoff", the node id and --commit <sha[:7+]>
   |   none -> author_missing    2+ -> author_ambiguous
   v
window = [ max(cycle entered todo, last edge on any node of the quest before this handoff), handoff ts ]
   |
   v
sum that session's isSidechain=false assistant messages in the window (dedupe message.id, last wins)
   |
   v
sink.1 append: author.tool_calls, author.tokens_{in,out,cache_read,cache_write}, run = claude:<sessionId>
```

## Pseudocode

```python
def scrape_authors(quest, claude_dir):
    edges = all_edges(bp3_q_r(quest))                       # every node, ordered by ts
    for h in [e for e in edges if e.edge == "handoff"]:
        sessions = [s for s in main_sessions(claude_dir)
                    if any(cast_handoff(c, h.node, h.commit) for c in s.bash_commands)]
        if len(sessions) != 1: tally("author_missing" if not sessions else "author_ambiguous"); continue
        start = max(entered_todo(h.node, h.cycle),
                    max((e.ts for e in edges if e.node != h.node and e.ts < h.ts), default=MIN))
        msgs = dedupe_last(m for m in sessions[0].assistant if not m.sidechain and start <= m.ts <= h.ts)
        append(quest, h.node, author_samples(msgs, h.cycle, run=f"claude:{sessions[0].id}"))
```

## Tables

| Field | Value |
|---|---|
| Intent | author cost per cycle, honest about being a window |
| Lane | standard |
| Output | the author pass of `metrics scrape`, its fixture, suite rows |
| Acceptance | the fixture cases above; nothing measures author spend today |
| Depends on | sink.1 - sample-sink |

| Case | Result |
|---|---|
| owner cast the handoff by hand (`!` in the session) | a `!` command is a user line, not a Bash tool call: `author_missing` |
| handoff cast from a shell outside Claude Code | `author_missing` |
| node created long before it was worked (cycle 1) | the window starts at the previous edge on another node, not at creation |
| compaction happened inside the window | the summary turn's usage counts once like any other message |

## Build notes (2026-11-21, found on real data)

These supersede the Diagram and Pseudocode above where they differ.

| Finding | Evidence | Rule it set |
|---|---|---|
| Handoff commands often pass the commit through a variable | 4 of 6 handoffs in this session: `--commit "$(git rev-parse HEAD)"` or `$C` | the casting call names `handoff` and the node as words, and either the command holds `commit[:7]` or its result holds the full commit (`Claude_tx.casts_handoff`) |
| A node id can be a substring of the command | unit: node `a` matched inside `handoff` | `has_word`: no id character on either side |
| A cycle's authoring can happen before the owner's resume | rules.4 round 4 was written while blocked; resume to handoff was 8 s | a window starts at the quest's previous edge, never a `resume` (`Metrics.author_spans`) |
| Ledger stamps are whole seconds, so adjacent windows share a second | design | `Claude_tx.assign` counts each message and tool call in the first window that holds it |
| Session files are big | this session: 45 MB, 20k lines | only assistant lines and tool results naming `handed_off` are parsed; `find_from` compares in place (scrape 2.2 s down to 1.2 s) |
| A later read can look like the cast (round 1, grader) | a session dated 2099 that greps nb's ledger turned nb authored, with five zero samples | the casting call must run inside the handoff's own window; a window with no messages of its own is `author_missing`, never zero |
| Results are often cut to `{ok, state}` | test-pyramid tier.2: `--commit "$SHA"` and a result without the commit; before the window check, a later read made these look authored | inside the window, a successful move to `handed_off` is evidence too; a result that shows a commit must show ours (first 6, one real result was cut after 6) |
| A line of an unexpected shape stopped the whole scrape | dogfood, this quest: a `queue-operation` line quoting "tool_result" and "handed_off" passed the cheap filter with no `message`; `member` raised | `Claude_tx.member` is total: a null message reads as absent fields |

On a scratch clone (round 2): constraints-context 10 of 10 handoffs
authored, test-pyramid 24 of 25 (1 `author_missing`), metric-collectors
4 of 4, 0 ambiguous. Round 1's 23 of 25 on test-pyramid held 3
authored only by later reads.
What the lifecycle shows: sink.1's authoring took 68 tool calls and
15.1M cache-read tokens, while its grade took 25 and 1.6M. A
long-lived main session re-reads its whole context on every call.

## Prose

The window is an approximation, and the name says so (QUEST.md,
Terms, R6). In an inline quest one node is in flight at a time, so
the quest's previous edge is a fair start line. Work in the window
that isn't authoring, such as a research side quest, gets counted.
Open question 3 asks whether that's close enough.

Author wall time is not scraped. Per-cycle todo dwell comes from the
ledger, and derive.1 owns it, so wall time has one source.
