---
status: frozen
date: 2026-11-13
promoted: null
---

# Session-log mining (scrape harness session logs into training data)

## Context

Frozen during the Exp 4 (tape and hooks) red-ink reopen of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/GOAL.md),
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
