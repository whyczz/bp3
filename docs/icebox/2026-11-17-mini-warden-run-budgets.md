---
status: frozen
date: 2026-11-17
promoted: null
---

# Mini-warden audit: run budgets and self-healing loops

## Context

Frozen 2026-11-17 by owner order during the graph-engine
quest (2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines),
to run **after this graph lands** — write it now, thaw on
landing. Owner, verbatim pressure:

- "I'm on the Muse Max plan and I'm already at 78% usage"
  — corrected by owner: that's the **weekly** allowance,
  burned in **two days** (this session alone: ~75M tokens).
  At that rate the week ends mid-week; run budgets below
  are survival limits, not optimizations.
- "The wall clock time for writing code and verifying is
  insane": followup.5's author node took ~35 min
  (49 tool calls, 13 files) for a workflow-script rewrite;
  its grade then ran 15+ min. followup.3 burned five
  cycles, three of them on one-word stale terms.
- North star: "fix the obvious mistakes, escalate quickly
  for other stuff — we're not doing rocket science."

This is the warden's manual first run
([2026-11-17-warden-plug-rules.md](2026-11-17-warden-plug-rules.md),
miner graph 3) done by hand over this graph's own tapes,
before any miner/profiler tooling exists. It feeds that
entry; it does not replace it.

## Sketch

One audit pass over the landed graph's runs (tapes,
ledgers, grade matrices — by ref, never copied wholesale),
producing a budget table and rule changes, not a tool:

| Budget | Owner target | Counted how |
|---|---|---|
| author node | **< 10 min** wall | handoff run: start→handoff cast |
| grade | **< 5 min** wall | grade run: start→verdict cast |
| owner pages | mechanical fixes only | blocked casts whose fix names exact file/line/text |

Audit steps:

1. **Measure.** Per node/grade this graph: wall time,
   tool calls, tokens where known, suite runs duplicated
   (warden row #9), full-`make check` count per cycle.
   Quote the tape/ledger refs; unmeasured stays unmeasured.
2. **Classify waste.** Bucket every over-budget minute:
   full-suite re-runs, model-in-data-plane copying,
   re-reads of unchanged state, provider retries, waiting.
3. **Self-heal rules.** The node loop heals obvious
   mistakes itself: stale retired terms, broken record
   links, dirty-tree residue, short-SHA/commit mismatch,
   render staleness — looper dispatches the named fix,
   no owner page (extends followup.5's mechanical-fix
   class with the concrete heal list found in step 2).
4. **Escalate fast.** Anything not on the heal list and
   not green in one grade: name it to the owner early
   with the failing row, instead of riding silent cycles.
5. **Output.** Budget table (target vs observed per
   node), heal-list additions as followup nodes or skill
   text, and the residual slow paths — each with an owner.

Deliberately not: no SQLite, no profiler, no automated
warden (those are the miner chain's graphs); no retroactive
blame — budgets bind future runs, this graph is the baseline.

## Blockers

- **Thaw order is fixed:** this graph lands first
  (landing.1 + owner promotion). The audit needs the
  complete run set, including the expensive nodes.
- **Token accounting is partial.** Some runs report no
  token totals; the audit quotes what tapes carry and
  marks the rest `unmeasured`, never estimates.
- **Budget enforcement point undecided:** skill text
  (looper instructed to split/stop) vs workflow code
  (hard timer) — decide from step-2 evidence, not before.
- **Max-plan usage is the owner's meter**, not readable
  from bp3; the audit can only cut bp3-side spend
  (calls, re-runs, copied bytes), not report plan %.

## Promotion trigger

Thaw the moment the graph-engine quest reaches
`goal_fin` (owner promotion on master). First acceptance:
the audit report over this graph's own runs, with the
budget table filled from tape/ledger refs and at least
the five known waste rows (full-suite-per-cycle,
audit re-runs, stale-term cycles, data-plane copying,
verdict races) each assigned a heal rule or an owner.
