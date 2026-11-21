---
status: frozen
date: 2026-11-18
promoted: docs/quests/2026-11-21-metric-collectors/
---

# Metric collectors: hooks, scrapers, derivers

## Context

Frozen 2026-11-18. Owner, verbatim: "the metrics, we have a
few, but imo this needs to be better. i want a set of
collectors, e.g. hooks, scrapers, and derivers."

All three kinds already exist, but they are scattered, and
no two share a shape:

| Kind | Exists today | Emits |
|---|---|---|
| hook (push, live) | `bp3 g hooks` (`src/graph/hooks.ml`) | `run_started`, `usage_recorded` (tokens in/out/cached/reasoning), `run_settled` as node ledger lines |
| scraper (pull, post-hoc) | `bp3 harness backtest` (`harness.ml` `do_backtest`) | usage parsed from muse-code / pi tapes |
| deriver (computed) | run-lifecycle derivations in `.git/bp3/` | lifecycle states; `setup_slow_s`/`depth_cap` thresholds in `config.json` |

Pressure: the mini-warden audit
([2026-11-17-mini-warden-run-budgets.md](2026-11-17-mini-warden-run-budgets.md))
wants budgets (author < 10 min, grade < 5 min). No collector
measures run wall time today, so it would stay "unmeasured".
The miner chain (tape scraper → profiler → warden) is one
scraper, one deriver and one consumer, each designed alone.

## Sketch

One sample shape, three collector kinds, one sink, and one
registry that names who owns each metric.

```ocaml
type kind = Hook | Scraper | Deriver
type sample = {
  metric : string;            (* "run.wall_s", "run.tokens_in" *)
  graph : string; node : string option; run_id : string option;
  value : float; at : string; (* ts *)
  source : string;            (* collector + evidence ref *)
}
(* registry: metric -> unit, agg (sum|avg|max|last), owner collector *)
```

```text
harness events ─ hook ────┐
tapes, logs ──── scraper ─┼─> samples ─> sink ─> derivers ─> samples ─> views
ledger ───────────────────┘                                  (bp3 g r, budgets, warden)
```

- Each metric has exactly one owning collector, so no number
  has two sources that can disagree.
- First set, the minimum for the budget table: `run.wall_s`,
  `run.tool_calls`, `run.tokens_{in,out,cached}`,
  `node.cycles`, `node.wall_s` (deriver), `cycle.suite_runs`.
- A deriver is a pure function: samples + ledger in, samples
  out. Re-running it is idempotent.

Deliberately not: no dashboard, no Prometheus, no LLM-scored
metrics, no new ledger edges.

## Blockers

- **Sink depends on the store decision.** It goes to
  `metrics.jsonl` or the SQLite store
  ([2026-11-18-sqlite-store.md](2026-11-18-sqlite-store.md)).
- **Two frameworks risk.** The miner entries each assume their
  own pipeline. Thaw must either refold them as collectors or
  say why not.
- **Ledger vs sink line:** `usage_recorded` is a ledger line
  today. Rule to decide: the ledger keeps facts that happen at
  a moment, and bulk numbers go to the sink?
- **Hook coverage differs by harness.** Muse has a per-call
  usage event (`PostLLMCall`); Claude Code does not (dropped
  2026-11-18), so a transcript scraper must fill that gap.
- **Identity:** a sample needs `run_id`; unbound sessions
  (`hooks.ml` "no binding witnessed") make orphan samples.
- **Sparse tape timestamps** (scraper blocker) cap wall-time
  precision.

## Promotion trigger

Thaw when the mini-warden audit thaws and needs `run.wall_s`,
or the next budget or cost question gets answered by hand-grep.
