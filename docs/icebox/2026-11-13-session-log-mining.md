---
status: frozen
date: 2026-11-13
promoted: null
---

# Session-log mining (scrape harness session logs into training data)

## Context

Frozen during the Exp 4 (tape and hooks) red-ink reopen of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/QUEST.md),
2026-11-13. Exp 4 settled that hooks emit deliberate facts
(`run_started`, `run_settled`, usage) as event lines, while
tape stays verbatim and unparsed. That leaves a second,
older source untouched: the harness's own session logs
(Muse session JSONL under its data dir; the predecessor
systems bp1/bp2 mined their session and pane archives the
same way). Those logs hold what hooks never saw: sessions
that predated the hooks, dead sessions, and the full text of
what models actually did — the raw material the warden idea
and scorecard training want.

This is mining, not state: a scraper produces derived
records for analysis. It must never write ledger lines or
move exps; the ledger is written at the moment a fact
happens, and a scraper operates after the fact.

## Sketch

- A read-only scraper over harness session logs (one input
  adapter per harness, starting with Muse session JSONL):
  extract per-Run timelines — prompts, tool calls, edges
  taken via `bp3 q`, refusals, token usage — keyed by any
  quest/exp/run identifiers present in the tape or commands.
- Output is a derived dataset (files in a research or
  dossier home, or a derived index): never ledger lines,
  never state. Anything it "discovers" that the ledger lacks
  is a reported gap, not a repair.
- Join against the ledger by run-id/commit: agreement is a
  health metric; disagreement names ledger gaps (facts that
  happened but were never emitted) and feeds Exp 4's hook
  coverage decisions.
- Deliberately not: no parsing of tape text into facts for
  state (the Exp 4 rule stands), no retroactive ledger
  writes, no surveillance framing — the subject is our own
  Runs' mechanics (context rent, bounce causes), not people.

## Blockers

- **Identity in logs.** Session logs do not reliably carry
  quest/exp/run identity; joining needs run-id or commit
  correlation, and unmatched sessions stay unmatched.
- **Harness drift.** Log formats change between harness
  versions; adapters rot. The scraper must fail loud on an
  unknown schema, never guess-parse.
- **Privacy and retention.** Session logs contain full
  prompts and outputs, including anything pasted into a
  session. Where the dataset lives, what is redacted, and
  how long it is kept are undecided and gate any thaw.
- **bp1/bp2 prior art unre-read.** The predecessor mining
  (session/pane archives, lesson extraction) informed this
  sketch from memory; promotion starts by re-reading what
  bp1/bp2 actually built and what it cost.
- **Exp 4 first.** Hook coverage decides what mining is
  even for: gaps the hooks close are gaps the miner need
  not reconstruct.

## Promotion trigger

Thaw when Exp 4's hooks are live and a concrete question
needs history hooks never saw — e.g. the warden's first
training set, a scorecard cost model, or a bounce-cause
study across more Runs than the ledger covers. A question
with a dataset shape promotes this; curiosity does not.

## Warden evidence: child misbehavior catalog (2026-11-17)

Added from the graph-engine quest
(2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines),
where workflow children misbehaved in repeatable,
mechanically detectable ways. This is the warden's
first concrete training set: not "watch everything",
but score these signals over tapes and run logs
(.git/bp3/<run-id>-log included) and file papercut
candidates. Detection is post-hoc mining; the warden
never writes state and never interrupts a Run.

| # | Misbehavior | Observed evidence | Mechanical signal |
|---|---|---|---|
| 1 | Transport child copied 513-line `git show --stat` verbatim into a JSON return; invalid JSON killed the grade | followup.3 grades x2 `audit_failure`, ~195s child time, zero matrix | child output contains output of a command it just ran; output/input token ratio >> 1 |
| 2 | Read children guessed repo root and ran the old-dialect `./bin/bp3`; whole step refused | bp3g-land attempts 1-2, grade attempt 1 (rename.1) | refusal plus cwd outside the desk in tape |
| 3 | node-loop accepted the `context` arg and never put it in the author brief; fixes arrived by hand-amendment | mvp.3 / followup.1 / dogfood cycles | dispatch arg not a substring of the child prompt |
| 4 | Audit children returned free-text evidence; rows downgraded to `missing` | "row carried no typed evidence" (config.1; mvp.3 reached cycle cap, blocked) | `evidence.kind` absent in returned rows |
| 5 | Grade and verify children raced verdict casts; the second ate `E_ILLEGAL_EDGE` | followup.1 and followup.2 grade returns ("expected verdict race") | two casts of the same edge inside one grade window |
| 6 | `bind-tape E_AMBIGUOUS` after nearly every Muse handoff (4 candidate tapes) | followup.2 defect 3; conductors trained to ignore refusals | same refusal code at least N times per handoff |
| 7 | Workflow reported `refused` when the handoff had actually committed | followup.2 author attempt; conductor verified state by hand | workflow outcome disagrees with a state read |
| 8 | Author ran the full wall-clock `make check` per cycle; no fast tier | followup.3 author: 55 tool calls, ~20 min, 310 files touched | duration / tool-call outlier vs node median |
| 9 | Audit re-ran suites the author had just run, uncached | grade matrices re-quoting `test/skills.sh` executions | same test command in author and audit tapes for one commit |

Four patterns cover the catalog, and they are the
warden's first checklist:

```text
(a) model in the data plane   copying bytes instead of pointing at them  (#1, #9)
(b) received-but-unsaid       arg in the envelope, absent from prompt    (#2, #3)
(c) parallel writers racing   two children, one state edge               (#5)
(d) refusal fatigue           same refusal until it becomes wallpaper    (#6, #7)
```

Fixes shipped mid-quest already validate the
catalog's usefulness: deskNote reads (#2), context
threading (#3), typed-evidence validations (#4),
and log-pointer transport (#1) each killed one row.
The warden's job is to find the next rows before
they burn a cycle.
