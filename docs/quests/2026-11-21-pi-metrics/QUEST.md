---
status: proposed
home_repo: bp3
date: 2026-11-21
---

# pi-metrics: what a pi grade costs, measured by bp3

TL;DR
`bp3 q <quest> metrics scrape` reads pi sessions too, so a grade run as
a headless `pi -p` is measured like a Claude Code subagent grade: wall,
tool calls, context, tokens, model. The one decision: pi has no separate
harness report to cross-check against, so a pi grade is
**self-checked** (its usage totals add up, and every tool call has its
result) and counted in its own `self_checked` bucket, never as `checked`.

ELI5
bp3 can already tell how much a Claude grader cost. This teaches it to
read pi's session logs too. To get real numbers, the quest grades its
own work with pi graders, then measures them.

## Context

Owner, 2026-11-21: "can we collect metrics for muse code and pi? lets
focus on pi". Asked where the data should come from, the owner chose
"pi graders, dogfood". metric-collectors left "the muse/pi refold" as
its Open question 2.

Ground, read this session:

| Fact | Source |
|---|---|
| sessions live at `~/.pi/agent/sessions/--<cwd with / \ : as ->--/<ts>_<id>.jsonl`; `--session-dir` puts them in that dir directly | pi docs `session-format.md:8-14`; probe below |
| entries form a tree (`id`/`parentId`); types `session`, `message` (roles system, user, assistant, toolResult), `model_change`, `thinking_level_change`, `usage`, `compaction`, `branch_summary`, `custom`… | `session-format.md:62-181` |
| every assistant message is one line with `usage {input, output, cacheRead, cacheWrite, reasoning?, totalTokens, cost}`, `model`, `provider`, `durationMs`; `reasoning` is already in `output` | `message-types.md:67-90`; bp3's 4 old sessions |
| `usage` entries, compaction and branch-summary `usage`, and tool-result `usage` also count toward session totals | `session-format.md:113-161`, `message-types.md:177` |
| tool calls are `toolCall` content blocks; results are `toolResult` messages carrying `toolCallId` | `session-format.md:90-92` |
| headless: `pi -p --tools read,bash --session-id <id>` ran in 4 s, printed `ok`, wrote one session (custom id in the header, `cwd` the repo), and its line obeyed `totalTokens = input + output + cacheRead + cacheWrite` (5046 + 5 = 5051) | probe, 2026-11-21, scratch `--session-dir` |
| bp3's pi sessions: 4 (2026-11-06..16), 0 bp3 edge casts; Run store: 129 runs, all muse-code, 0 pi | read this session |
| `metrics scrape --pi-dir` refuses today: `E_USAGE` "unknown metrics scrape argument: --pi-dir" | observed |
| `Metrics.model_ok` accepts `claude-*`, `unknown`, `other` only; pi's `gpt-6.1-sol` would read as `other` | `src/quest/metrics.ml` |

## Terms

| Term | Meaning |
|---|---|
| pi session | one `.jsonl` file pi writes per session: a `session` header (`id`, `cwd`), then entries |
| `Pi_tx` | new module (`src/quest/pi_tx.ml`): reads a pi session into the same `Claude_tx.cost` record a Claude transcript gives |
| pi grader | one headless `pi -p --tools read,bash --session-id <id> "<cold brief>"` run from the desk; its session is the grade transcript |
| self-check | `Pi_tx.self_checks`: every usage line has all four counts and `totalTokens = input + output + cacheRead + cacheWrite`, and every `toolCall` has a `toolResult` |
| `self_checked` | tally bucket: a pi grade that passed its self-check (written). One that fails is `mismatched` (nothing written, exit 1) |
| pi dirs | the scrape's pi session dirs: `~/.pi/agent/sessions/--<repo path>--` and each desk's `--<repo path>-.bp3-worktrees-<slug>--`, logical and real paths, plus any `--pi-dir` |
| model family | the closed list `Metrics.model_ok` accepts: `claude-`, `gpt-`, `gemini-`, `grok-`, each followed by `[a-z0-9.-]` |

## Inputs

| Input | Source |
|---|---|
| pi session files | pi dirs; `--pi-dir <dir>` (repeatable) replaces the default pi dirs, as `--claude-dir` does for Claude |
| grade edges | the quest's node ledgers, as today |
| Claude Code transcripts | unchanged |

## Outputs

| Output | Shape |
|---|---|
| grade samples from pi | the existing `grade.*` metrics, `source` grade-transcripts, `run` `pi:<sessionId>`, `model` the pi model when its family is known, else `other` |
| scrape JSON | gains `pi_dirs`; per-node tally gains `self_checked` |
| exit | 1 also when a pi grade fails its self-check (`mismatched`) |

## Acceptance gates (observed today, then design trace)

Observed 2026-11-21:

```text
$ bp3 q 2026-11-21-metric-followups metrics scrape --pi-dir /nonexistent
{"ok":false,"code":"E_USAGE","detail":"unknown metrics scrape argument: --pi-dir"}
```

Design trace, after the quest:

```text
reader.1   unit: a synthetic pi session -> cost {wall_s, tool_calls, context_end, tokens_*, model "gpt-6.1-sol"};
           a line with totalTokens off by one -> self-check false; a toolCall with no toolResult -> self-check false
scrape.1   test/metrics.sh: a pi grader session whose first prompt names node nd and its sha, in the window
           -> nd.self_checked 1, 7 grade.* samples with run "pi:<id>"; the same grade with a Claude transcript too
           -> ambiguous; a broken total -> mismatched, exit 1
dogfood    bp3 q 2026-11-21-pi-metrics metrics r -> every grade of this quest measured, run pi:*, model gpt-6.1-sol
all        make check-full rc 0
```

## Goal and why

Measure pi the way Claude Code is measured, so the two harnesses can be
compared on the same kind of work. This is the first side-by-side: this
quest's pi grades next to metric-followups' Claude grades (median 201 s).

## Success picture

`bp3 q 2026-11-21-pi-metrics metrics r` shows every grade of this quest
measured from its pi session, self-checked, with the pi model named. The
scrape still reads Claude Code exactly as before.

## Scope

| In | Out |
|---|---|
| `Pi_tx` reader and self-check (reader.1) | pi author windows: no pi-authored handoff exists yet (Open question 1) |
| pi grades in `metrics scrape`, `--pi-dir`, the `self_checked` bucket (scrape.1) | a `cost_usd` metric from pi's dollar cost (Open question 2) |
| model families in `Metrics.model_ok` (reader.1) | `BP3_HARNESS=pi` for pi-cast edges (refused today, `E_IDENTITY`; follow-up) |
| induct-inline names pi as a grader runtime (skills.1) | muse-code sessions (owner: "lets focus on pi") |
| | `PI_CODING_AGENT_SESSION_DIR` and the `sessionDir` setting (default dirs plus `--pi-dir` only) |

## Constraints at approval

Constraints pass: none. The reader is OCaml with yojson, and
`@earendil-works/pi-coding-agent` is already a signed node library;
running `pi` as a grader adds no language or shipped surface.
Common-sense pass: CONTEXT.md has no claim on how others measure agent
cost, so none is cited. pi's own `/session` command shows a session's
token usage and cost (pi docs `sessions.md:26`). reader.1 checks its
totals against that by hand once, on the probe session.

## Human touchpoints

| When | Owner |
|---|---|
| approval of this frame | owner |
| each grade | one headless pi grader per commit, cast by this session as returned (owner's sync answer "pi graders, dogfood") |
| promotion | owner |

Decisions (owner, 2026-11-21):

| Question | Owner's answer |
|---|---|
| where pi data comes from | "pi graders, dogfood" |
| approve the 3-node frame | "Approve, yolo": self-check as framed (no JSON oracle), a headless pi grader per commit, no pages until promotion |

## Nodes

### Milestone: reader

| Node | TL;DR |
|---|---|
| [reader.1 - pi-session](nodes/node-reader-1-pi-session/NODE.md) | `Pi_tx` reads a pi session into a cost record, with a self-check; `model_ok` knows model families |

### Milestone: scrape

| Node | TL;DR |
|---|---|
| [scrape.1 - pi-grades](nodes/node-scrape-1-pi-grades/NODE.md) | the scrape joins pi grader sessions to grade edges, beside Claude transcripts, into `self_checked` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - pi-grader](nodes/node-skills-1-pi-grader/NODE.md) | induct-inline names `pi -p` as a grader runtime, with its command and brief rules (skill node) |

## Scorecard

From `bp3 q 2026-11-21-pi-metrics metrics r`: pi grade wall, tool calls
and tokens per node, beside metric-followups' Claude grades. Author
windows stay Claude Code (this session).

## Risks and red chair

Strongest attack: "self-check is weaker than Claude's cross-check: a
reader that misreads wall time or drops a whole message still passes."
Settled in the design: the bucket is named `self_checked`, so no
readout claims more than it checked. The totals law catches a renamed
or missing usage key (it can't add up), and the `toolCall`/`toolResult`
pairing catches a reader that drops calls. Wall stays unverified, and
the build notes say so. A stronger oracle (pi's `--mode json` stream,
saved by the conductor) is Open question 3.

Second attack: "pi grades by a different model make the quest's own
verdicts weaker." Not settled by design; it's the owner's call at sync.
The brief stays the same cold brief Claude graders get, and the grader
still runs `make check-full`.

Attack on the source (the owner's prompt): "pi is on hold; nothing runs
it, so there's nothing to measure." Settled: the dogfood makes the data.
Every grade of this quest is a pi session, and grades cast before
scrape.1 lands are measured afterwards, because the scrape is
idempotent and reads old sessions.

## Open questions

1. When pi authors (a pi session casts handoffs), do pi author windows
   reuse scrape.2's rule with `bash` toolCalls? Owner: the first quest
   authored in pi.
2. Should pi's dollar `cost.total` become a `grade.cost_usd` metric,
   when only pi reports it? Owner: owner, after the scorecard.
3. Is self-check enough, or should the conductor save pi's
   `--mode json` stream as an independent report? Owner: owner, after
   reader.1's numbers.

## Node diagram

```text
reader.1 ──> scrape.1 ──> skills.1
 (Pi_tx)      (scrape)     (induct-inline)
every grade, from reader.1 on: a headless pi grader; measured once scrape.1 lands
```
