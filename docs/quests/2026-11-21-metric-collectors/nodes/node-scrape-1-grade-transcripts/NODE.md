---
date: 2026-11-21
quest: ../../QUEST.md
node: scrape.1
status: proposed
---

# scrape.1 - grade-transcripts: each grade's Claude Code subagent, counted once, checked twice

## TL;DR

`bp3 q <quest> metrics scrape` finds, for every `grade` edge, the
Claude Code subagent transcript that did the grading. It counts that
transcript once per message, checks it against the harness's own
report, and writes seven `grade.*` samples through sink.1. Ambiguous
or mismatched grades write nothing and are named in the verdict.

## Acceptance gates

Observed 2026-11-21 by hand (`jq`) on the rules.4 round-4 grader,
the oracle this node must reproduce:

```text
transcript: 88 lines, 50 message ids, 52 tool_use ids,
            20:53:27.705 -> 21:14:47.995 (1280 s),
            in 100, out 77424, cache_read 5505097, cache_write 170483,
            last message in+cache_read+cache_write+out = 173523
harness report: tool_uses 52, duration_ms 1280300, subagent_tokens 173523
```

Design trace:

```text
$ bp3 q 2026-11-19-constraints-context metrics scrape
{"ok":true,"nodes":{"node-rules-4-lint-hardening":{"grades":4,"written":28,"skipped":0,
  "ambiguous":0,"mismatched":0,"unchecked":0,"owner":0}, ...}}
$ bp3 q 2026-11-19-constraints-context metrics r | jq '.nodes["node-rules-4-lint-hardening"].cycles["4"].grade'
{"wall_s":1280,"tool_calls":52,"context_end":173523,"tokens_in":100,"tokens_out":77424,
 "tokens_cache_read":5505097,"tokens_cache_write":170483,"model":"claude-opus-5-5",...}
$ bp3 q 2026-11-19-constraints-context metrics scrape      # again: written 0, skipped 28
```

```yaml
objective: every Claude Code grade gets its cost from its own transcript, matching the harness report, or is named as why not
prove by:
  - a fixture in test/ with synthetic transcripts (no real prompts) for: one clean grade; a message repeated over 3 lines;
    two candidates in one window; a harness report that disagrees; no harness report; an owner-graded cycle
  - the observed run on constraints-context and test-pyramid on this machine
  - make check-full
done when:
  - rules.4 cycle 4 reads exactly the oracle above
  - the repeated message counts once (last snapshot), the two-candidate grade is "ambiguous", the disagreeing one is "mismatched" with exit 1 and no samples
  - every grade edge in both quests lands in exactly one of: written, ambiguous, mismatched, unchecked, owner
  - a second scrape writes 0; the scrape of constraints-context takes under 2 s
```

## Diagram

```text
bp3 q r (grade edges: node, cycle, commit, handoff ts, grade ts)
        |
        v
candidates = subagent transcripts in ~/.claude/projects/<repo slug>*/<session>/subagents/
   where first prompt names the node id and commit[:7+]
     and first ts >= handoff ts, last ts <= grade ts
        |
   0 -> owner (no grader transcript)   2+ -> ambiguous   1 -> count
        |
count: dedupe message.id (last wins), tool_use ids, wall, tokens, context_end
        |
check vs harness report (parent transcript, matched by meta.json toolUseId)
   differs -> mismatched (exit 1, nothing written)   missing -> unchecked (written)
        |
        v
sink.1 append: 7 grade.* samples, run = claude:<sessionId>/<agentId>
```

## Pseudocode

```python
def scrape_grades(quest, claude_dir):
    for node, cycle, commit, t_hand, t_grade in grade_edges(bp3_q_r(quest)):
        cands = [t for t in subagent_transcripts(claude_dir)
                 if names(t.first_prompt, node, commit[:7])
                 and t.first_ts >= t_hand and t.last_ts <= t_grade]
        if not cands: tally("owner"); continue
        if len(cands) > 1: tally("ambiguous"); continue
        t = cands[0]
        msgs = {m.id: m for m in t.assistant_lines}.values()   # last snapshot wins
        cost = Cost(wall_s=t.last_ts - t.first_ts,
                    tool_calls=len({b.id for l in t.assistant_lines for b in l.tool_uses}),
                    tokens=sum_fields(msgs), context_end=total(last(msgs).usage),
                    model=last(msgs).model)
        rep = harness_report(t.meta.toolUseId)                 # <usage> in the parent transcript
        if rep and not agrees(cost, rep):                      # tool_uses ==, |wall - ms/1000| <= 1, context ==
            tally("mismatched"); continue
        tally("written" if rep else "unchecked")
        append(quest, node, samples(cost, cycle, run=f"claude:{t.session}/{t.agent}"))
```

## Tables

| Field | Value |
|---|---|
| Intent | cost per grade for Claude Code graders, from files already on disk |
| Lane | standard (reads machine-local harness files; writes only through sink.1) |
| Output | `metrics scrape` in `src/quest/` (OCaml, yojson), fixture transcripts under `test/`, a suite row |
| Acceptance | the oracle row and the fixture cases above; the verb does not exist today |
| Depends on | sink.1 - sample-sink |

| Field read | From | Note |
|---|---|---|
| `message.id`, `message.usage.*`, `message.model`, `timestamp` | subagent `agent-*.jsonl`, `type: assistant` | repeated per content block; last snapshot wins |
| `tool_use` block ids | same lines | unique ids, not lines |
| first prompt | first `type: user` line | read to match, never stored |
| `toolUseId` | `agent-*.meta.json` | joins to the parent's report |
| `<usage>` block | parent `<session>.jsonl` | `subagent_tokens`, `tool_uses`, `duration_ms` |

| Case | Verdict bucket |
|---|---|
| owner graded (no transcript in the window) | `owner` |
| two transcripts name the node and commit in the window | `ambiguous` |
| report disagrees | `mismatched`, exit 1 |
| no report found | `unchecked`, samples written |
| line shape unknown (no `message.id`) | the line counts toward `skipped_lines`, never as zero tokens |
| desk sessions (`~/.claude/projects/<slug>--bp3-worktrees-...`) | scanned: every project dir whose slug starts with the repo's |

## Build notes (2026-11-21, found on real data)

| Finding | Evidence | Rule it set |
|---|---|---|
| A grader resumed by a follow-up keeps writing after its first report | 4 of 43 reports in this repo's main session: the transcript has 1-4 more tool calls; each resumed stop queues a later report keyed by `<task-id>` alone, matching the whole transcript | reports are keyed by `<task-id>` and `<tool-use-id>`, last wins; the scraper looks up the agent id first, so its last report covers the whole transcript; the check reads lines up to that report's `r_at` (`parse ~until`) |
| The transcript can log the final message's output short | context 62 to 1009 tokens under `subagent_tokens` on 4 of 43 (at most 0.74%), never over | `agrees`: tool calls exact, wall within 1 s, context at most 1% under and never over |
| A usage key read as 0 passes as a cheap grade | grader (round 1): with missing keys as 0 and a 5% band, a renamed `output_tokens` would still pass on 39 of 43 | `usage_of` takes all four counts or none; a line without them is skipped (`bad_usage`), and `checks` fails any cut holding one |
| The report also appears quoted in the parent's own messages | 5 assistant lines holding `<usage>...` text | reports come from `queue-operation` `enqueue` lines only |
| A model field is a place text could ride | grader probes: `sk-ant-api03-...` passed `id_ok`; `other\nhunter2` passed Str's `$` | `Metrics.model_ok` is a character check (`claude-<lowercase>`, `unknown`, `other`); `ts_ok` checks the match end, not `$`; the reader records any other model as `other` |
| `wall_s` is the transcript's span, so a resumed grader's idle gap counts | test-pyramid tier.1 cycle 2: 18412 s | left to derive.1 (a span is not active time); `tokens_out` can also be short by the final snapshot (up to 1009) |

After the rules, on a scratch clone: constraints-context 7 checked
and 3 owner-graded; test-pyramid 23 checked and 1 owner-graded;
metric-collectors 2 checked; 0 mismatched, 0 skipped lines.

## Prose

The harness report is the trick that makes an unofficial format
safe enough to use. The transcript is undocumented, but the same
harness also tells the parent three of the numbers directly. If the
scraper and the report disagree, the scraper is wrong, and the
grade is flagged instead of recorded (QUEST.md, R1).

Last snapshot, not first: Claude Code streams a message as several
lines that repeat the usage. ccusage keeps the first and its issues
report undercounted output; obol-core keeps the last (QUEST.md, C1).

Joining without a marker: past grader briefs already name the node
id and the commit, and the handoff-to-grade window bounds the time.
Requiring a marker in briefs would leave every past grade
unmatched. read.1 makes "name the node id and the SHA" an explicit
rule for future briefs.

`input_tokens` is near 1 per message on cached calls. The spend
sits in the cache fields, and this node reports each field
separately, never one blended "tokens" number.
