---
status: proposed
home_repo: bp3
date: 2026-11-21
---

# metric-collectors: what a grade costs, measured by bp3

TL;DR
`bp3 q <quest> metrics r` answers what each grade and each author
cycle cost: wall time, tool calls and tokens, per node and cycle,
joined to the ledger edge it belongs to. Numbers come from Claude
Code transcripts (a scraper), live in a `metrics.jsonl` per node
written only by `bp3 q` (the sink), and roll up through a pure
deriver. The one decision made: questions first. Each collector
exists because a number was being grepped by hand.

ELI5
Every time a reviewer agent grades work, it spends minutes and
millions of tokens, and today nobody writes that down except by
hand. This quest teaches bp3 to read the agent's own log
afterwards, write the numbers next to the grade they belong to,
and add them up per node.

## Context

Promoted from the icebox entry, copied verbatim to
[ICEBOX.md](ICEBOX.md). Owner, 2026-11-18: "the metrics, we have a
few, but imo this needs to be better. i want a set of collectors,
e.g. hooks, scrapers, and derivers." Owner, 2026-11-21: "now lets
focus on the metrics collection quest".

Trigger, checked 2026-11-21. Both halves fired:

- The graph-engine quest reached `goal_fin` (merge `6d2cd11`,
  2026-11-18), which thaws mini-warden, and mini-warden needs run
  wall time.
- A cost question was answered by hand-grep: the fast-grader draft
  (`docs/quests/2026-11-19-fast-grader/QUEST.md`, Context) measured
  "grade wall time median about 11 min (4-37), 78k-198k tokens of
  context each" from subagent transcripts by hand.

Owner decisions, 2026-11-21 (sync, before framing):

| Question | Owner's answer |
|---|---|
| Which read of "a set of collectors" | "Questions first": one collector per hand-grepped number, a shared sample shape |
| First number to land | "Cost per grade": wall, tokens and tool calls per grade and per author cycle |
| Where samples live | "jsonl, written by bp3": a `metrics.jsonl` per node, stored like the ledger |
| Harnesses in the first cut | "Claude Code first": muse and pi keep their hook and backtest; refold later |
| Approval of this file | "Approve as-is" |

What exists today (read 2026-11-21):

| Kind | Today | Gap |
|---|---|---|
| hook | `bp3 q hooks` (`src/quest/hooks.ml`): `run_started`, `usage_recorded`, `run_settled` ledger lines | muse only; every grade this week ran in Claude Code |
| scraper | `bp3 harness backtest` (`src/quest/harness.ml` `do_backtest`) | muse-code and pi tapes only |
| deriver | `timing` in `bp3 q r` (`src/quest/render.ml`): `wall_s`, `wait_s`, `dwell_s` per state, `cycles` | per node; no tokens, no tool calls, nothing per grade |

Observed 2026-11-21, by hand with `jq`, on the rules.4 round-4
grader transcript (`~/.claude/projects/-Users-whycz-m-bp3/<session>/subagents/agent-<id>.jsonl`,
meta description "Grade rules.4 round 4"):

| Field | Transcript | Harness's own report to the parent |
|---|---|---|
| lines / messages | 88 lines, 50 unique `message.id` | |
| tool calls | 52 unique `tool_use` ids | `tool_uses` 52 |
| wall | 20:53:27.705 to 21:14:47.995, 1280 s | `duration_ms` 1280300 |
| context at the end | 173,523 | `subagent_tokens` 173523 |
| tokens: input / output | 100 / 77,424 | |
| tokens: cache read / cache write | 5,505,097 / 170,483 | |

Two lessons from that table shape the design:

- **The hand-measured number was the wrong quantity.**
  `subagent_tokens`, and fast-grader's "78k-198k tokens", is the
  context size at the end. The grade processed about 5.75M tokens,
  33 times that, almost all of it cache reads.
- **A naive sum double counts.** Claude Code writes one line per
  content block and repeats the usage on each, so 88 lines carry 50
  messages. The harness's own report gives a second, independent
  source for three of the numbers. The scraper cross-checks against
  it.

## Terms

- **sample**: one number about one thing: `{metric, quest, node, model,
  cycle, run, value, at, source}`. No free-text field.
- **metric**: a dotted name for what a sample measures, e.g.
  `grade.tokens_cache_read`; registered once, with its unit and
  owner.
- **registry**: the table of metrics in `src/quest/metrics.ml`: name,
  unit, how a node combines it (`sum`, `max`, `last`), and the one
  collector that owns it.
- **owner**: the one collector allowed to write a metric; two
  sources for one number is a refused write.
- **collector**: code that writes samples; one of three kinds,
  spelled as in the icebox entry.
- **hook**: a collector the harness pushes to while it runs
  (`bp3 q hooks`, muse); none new in this quest.
- **scraper**: a collector that reads a harness's files after the
  fact (`bp3 q <quest> metrics scrape`).
- **deriver**: a pure function from samples and ledger to samples;
  re-running it changes nothing.
- **sink**: `docs/quests/<quest>/nodes/<node>/metrics.jsonl` on the
  node's state branch, append-only, written only by `bp3 q`; GENERATED
  like `ledger.jsonl`.
- **run**: the key of the thing measured, for Claude Code
  `claude:<sessionId>/<agentId>` (a subagent) or
  `claude:<sessionId>` (a main session window); not a bp3 Run id.
- **grade transcript**: the Claude Code subagent transcript whose
  first prompt names the node and the graded commit, and that runs
  inside that cycle's `handed_off` window.
- **author window**: the main-session messages between a cycle's
  start (its entry to `todo`) and its `handoff` edge, in the session
  that cast that handoff.
- **harness report**: the `<usage>` block (`subagent_tokens`,
  `tool_uses`, `duration_ms`) the harness hands the parent when a
  subagent ends; the scraper's cross-check.
- **cost** (of a grade or cycle): the samples for it, read together;
  never a dollar figure (pricing is out of scope).

## Inputs

| Input | Source | Notes |
|---|---|---|
| ledger edges | `bp3 q` (handoff, grade timestamps, commit, cycle) | the join key; never parsed by hand |
| Claude Code transcripts | `~/.claude/projects/<repo-slug>/` (`<session>.jsonl`, `<session>/subagents/agent-*.jsonl`, `.meta.json`) | machine-local; `--claude-dir` overrides |
| harness report | `<usage>` blocks in the parent session transcript | cross-check only |
| registry | `src/quest/metrics.ml` | compiled in |

## Outputs

| Output | Shape |
|---|---|
| `bp3 q <quest> metrics scrape` | JSON verdict: `{ok, written, skipped, ambiguous, mismatched}` counts per node; exit 0, 1 on a mismatch |
| `bp3 q <quest> metrics r` | JSON: per node, per cycle, `grade` and `author` cost, plus node and quest roll-ups |
| `metrics.jsonl` | one sample per line on the node's state branch; one commit per node per scrape |
| refusals | `E_METRIC_UNKNOWN` (no registry row), `E_METRIC_OWNER` (wrong collector) |

## Acceptance gates (design trace, oracle numbers observed)

```text
$ bp3 q 2026-11-19-constraints-context metrics r          # today
{"ok":false,"error":{"code":"E_USAGE",...}}                # observed 2026-11-21, rc=2

$ bp3 q 2026-11-19-constraints-context metrics scrape      # after the quest
{"ok":true,"nodes":{"node-rules-4-lint-hardening":{"grades":4,"written":28,"author_written":20,"ambiguous":0,"mismatched":0},...}}
$ bp3 q 2026-11-19-constraints-context metrics scrape      # again
{"ok":true,"nodes":{"node-rules-4-lint-hardening":{"written":0,"skipped":48,...},...}}
$ bp3 q 2026-11-19-constraints-context metrics r | jq '.nodes["node-rules-4-lint-hardening"].cycles["4"].grade'
{"wall_s":1280,"tool_calls":52,"context_end":173523,"tokens_in":100,
 "tokens_out":77424,"tokens_cache_read":5505097,"tokens_cache_write":170483,
 "model":"claude-opus-5-5","run":"claude:<session>/<agent>"}
```

```yaml
objective: bp3 produces, from files on disk, what each grade and author cycle cost, and the numbers match the harness's own report
prove by:
  - make check-full (the new unit and fixture rows)
  - the trace above on this repo's constraints-context and test-pyramid quests
done when:
  - rules.4 cycle 4's grade reads exactly the oracle row above (tool_calls 52, wall 1280, context_end 173523)
  - a second scrape writes 0 samples
  - every grade in both quests either has a grade cost or is named in `ambiguous` or as owner-graded, none silently missing
  - fast-grader's hand table is re-derived by `metrics r` and its token column corrected to spend
```

## Goal and why

Grades are bp3's slow loop (CONTEXT.md, bp3 lessons, 2026-11-19).
Every fix to that loop, fast-grader first, gets judged by numbers
someone currently greps by hand, and the one hand number we have
measured the wrong thing. A quest that changes the grade loop
should be able to read its own cost from `bp3 q`.

## Success picture

- `bp3 q <quest> metrics r` shows each grade's wall, tool calls and
  tokens, and each author cycle's tool calls and tokens, for every
  node of the two quests on master that ran in Claude Code.
- The numbers agree with the harness report wherever both exist.
- The conductor skills scrape after every grade, so this quest's own
  later nodes show up in their own `metrics r` (dogfood).

## Scope

| In | Out |
|---|---|
| sample shape, registry, `metrics.jsonl` sink, `metrics r` | SQLite (needs a sign-off; `2026-11-18-sqlite-store` stays frozen) |
| Claude Code grade transcripts scraper | refolding the muse hook and the muse/pi backtest into samples |
| Claude Code author-window scraper | a Claude Code `SubagentStop` hook as a push trigger (Open question 1) |
| one deriver: node and quest roll-ups | budgets and flags (mini-warden consumes `metrics r` later) |
| conductor skills run the scraper; docs name the new GENERATED file | dashboards, OTEL export, dollar pricing, LLM-scored metrics, new ledger edges |

## Constraints at approval

- **Constraints pass:** nothing added. OCaml with yojson and unix,
  both listed; the new verbs live under the `bp3 q` door (the bp3
  CLI surface). Reading `~/.claude` reads a harness's files; harness
  CLIs are surfaces bp3 runs on (CONSTRAINTS.md, Surfaces).
- **Common-sense pass:** see Risks and red chair, rows C1 and C2.

## Human touchpoints

| When | Who | What |
|---|---|---|
| approval | owner | approves this file; promotion deletes the icebox entry |
| grading | owner or fresh grader | decided at `/induct-inline` |
| promotion | owner | `goal_fin` |

## Nodes

### Milestone: sink

| Node | TL;DR |
|---|---|
| [sink.1 - sample-sink](nodes/node-sink-1-sample-sink/NODE.md) | the sample type, the registry with one owner per metric, `metrics.jsonl` appends through `bp3 q`, and `metrics r` |

### Milestone: scrape

| Node | TL;DR |
|---|---|
| [scrape.1 - grade-transcripts](nodes/node-scrape-1-grade-transcripts/NODE.md) | find each grade's Claude Code subagent transcript, count it once per message, check it against the harness report, write `grade.*` samples |
| [scrape.2 - author-window](nodes/node-scrape-2-author-window/NODE.md) | the session that cast each handoff, its messages between cycle start and handoff, as `author.*` samples |

### Milestone: derive

| Node | TL;DR |
|---|---|
| [derive.1 - node-cost](nodes/node-derive-1-node-cost/NODE.md) | a pure deriver for node and quest roll-ups (grades, spend, median grade wall), folding the existing `timing` |

### Milestone: read

| Node | TL;DR |
|---|---|
| [read.1 - conductor-scrapes](nodes/node-read-1-conductor-scrapes/NODE.md) | induct and induct-inline scrape after each grade cast; using-bp3, CLAUDE.md and AGENTS.md name `metrics r` and the GENERATED file |

## Scorecard

| Row | Read from |
|---|---|
| grade cost per node of this quest, from scrape.1 on | `bp3 q 2026-11-21-metric-collectors metrics r` |
| scrape wall on a 6-node quest | `time bp3 q <quest> metrics scrape`, target under 2 s |
| fast-grader's table, re-derived | `metrics r` on test-pyramid |

## Risks and red chair

Strongest attack, recorded: **"`timing.dwell_s.handed_off` already
gives grade wall; this is a quest to print tokens."** It changed the
design: wall was never the hard part. The hand token number measured
context, not spend, so the quest is justified by fixing a wrong
number, not by adding one. The acceptance pins spend fields and
corrects fast-grader's column.

| # | Lens | Concern | Severity | Ends in |
|---|---|---|---|---|
| R1 | engineering | The Claude Code transcript format is not a published contract; a change makes silent wrong numbers | major | settled in scrape.1: every grade is cross-checked against the harness report (tool calls, wall within 1 s, context at the end); a mismatch writes nothing and exits 1. Unknown line shapes count as `skipped`, never zero |
| R2 | engineering | double counting from repeated usage lines | major | settled in scrape.1: one message per `message.id`, last snapshot wins; a fixture row repeats a message three times |
| R3 | engineering | wrong join: a red-chair or respawned agent in the same window names the same node and SHA | major | settled in scrape.1: two candidates means `ambiguous`, nothing written; owner grades have no transcript and are counted as `owner` |
| R4 | security | transcripts hold prompts and possibly secrets; `metrics.jsonl` lives on refs that get pushed | major | settled in sink.1: the sample type has no free-text field; `source` and `run` are ids; a unit test refuses a string value |
| R5 | engineering | git as a database: one commit per sample would repeat the 185-spawn problem (`2026-11-18-sqlite-store`) | major | settled in sink.1: one commit per node per scrape; scorecard row under 2 s |
| R6 | product | the author window over-counts: the main session does other work between todo and handoff | minor | named in Terms as a window, not "the author's spend"; Open question 3 |
| R7 | data | the ledger labels Claude Code work `harness: muse-code` (`claude` is refused with E_IDENTITY) | minor | samples take model and harness from the transcript, not the ledger; points at `2026-11-18-claude-code-engine` |
| C1 | common sense | how others do it: scrape the JSONL per day or session (ccusage, ccstats, obol-core), deduping on `message.id` and `requestId`; ccusage keeps the first snapshot and undercounts output (issues #888, #901), obol-core keeps the last | | adopted: keep the last snapshot (R2). We differ by joining to ledger edges, per grade, which none of them do. Sources: [ccusage data loader](https://www.mintlify.com/ryoppippi/ccusage/api/library/data-loader), [obol-core claude.rs](https://docs.rs/crate/obol-core/0.4.0/source/src/transcript/claude.rs), ccusage issues #888 and #901 (seen in search results through a mirror, not fetched; check github.com/ryoppippi/ccusage before citing), search run 2026-11-21. Single-source third-party claims, so not admitted to CONTEXT.md. Our own observation backs R2 either way: 88 lines, 50 messages |
| C2 | common sense | the first-party path: Claude Code exports OpenTelemetry metrics (`claude_code.token.usage`) to a collector | | not taken: it needs a collector service (a surface without sign-off), is in beta, has no backfill, and the subagent attribution found is in traces, not metrics ([monitoring usage](https://code.claude.com/docs/en/monitoring-usage), [agent SDK observability](https://code.claude.com/docs/en/agent-sdk/observability), checked 2026-11-21) |

Source red chair (7.5), on the icebox entry:

| # | The entry assumed | Re-decided |
|---|---|---|
| S1 | samples keyed by a bp3 `run_id` (`run.wall_s`, `run.tool_calls`) | Claude Code graders are not bp3 Runs; `run` keys transcript ids (Terms) |
| S2 | hooks are the push path | Claude Code has no per-call usage hook; transcripts are the only per-call source |
| S3 | the sink waits on the store decision | decided by the owner: jsonl written by bp3 |
| S4 | thaw must refold the miner chain or say why not | why not: `tape-scraper-sqlite`, `run-profiler-chrome-trace` and mini-warden target muse/pi tapes and SQLite; they stay frozen and write through sink.1 when they thaw |
| S5 | `cycle.suite_runs` in the first set | dropped: no hand-grepped question asks for it today |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Should a Claude Code `SubagentStop` hook trigger the scraper (a push hook), replacing read.1's "conductor remembers" rule? | owner, after read.1 lands |
| 2 | When does the muse `usage_recorded` ledger line move to samples (the ledger-vs-sink rule: moments in the ledger, bulk numbers in the sink)? | next metrics quest |
| 3 | Is the author window close enough, or should author cost wait for author subagents (induct with children)? | owner, after scrape.2's readout |

## Node diagram

```text
sink.1 sample-sink
   |
   +------------------+
   v                  v
scrape.1 grade     scrape.2 author
   |                  |
   +--------+---------+
            v
      derive.1 node-cost
            |
            v
      read.1 conductor-scrapes   (skill node)
```
