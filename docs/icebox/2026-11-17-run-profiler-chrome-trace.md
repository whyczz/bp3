---
status: frozen
date: 2026-11-17
promoted: null
---

# Run profiler — flame chart / Chrome trace (miner, graph 2 of 3)

## Context

Frozen 2026-11-17 with the tape scraper
([2026-11-17-tape-scraper-sqlite.md](2026-11-17-tape-scraper-sqlite.md)).
`make check` "feels slow" and author cycles burn ~20 min, but
today nobody can point at *where* a run's wall-clock went.
PyTorch-profiler framing, owner's mapping: CPU = host = the
LLM thinking/generating; GPU = device = CLI/tool calls
executing. Output a Chrome trace (JSON, opens in Perfetto /
chrome://tracing) — human-readable as a flame chart, and the
same JSON is LLM-parseable for hotspot summaries. Feeds the
warden ([2026-11-17-warden-plug-rules.md](2026-11-17-warden-plug-rules.md)).

## Sketch

```text
miner.sqlite ─> derive intervals ─> trace.json (Chrome Trace Event format)
  llm   interval = gap between tool-call end and next tool-call start   (ph:"X", cat:"llm")
  tool  interval = tool_call started..ended                             (ph:"X", cat:"tool")
  state interval = ledger edge timestamps (handoff/grade/land)          (ph:"i", cat:"state")
pid = node, tid = run_id  →  one flame lane per run, stacked by node
```

| View | Consumer | Question it answers |
|---|---|---|
| Perfetto flame chart | human | "where did followup.3's cycle-3 go?" |
| `trace.json` + hotspot table (top-N by cat/tool) | LLM | "name the slow path, cite intervals" |
| per-tool rollup (`tool`, count, total, p50/p95) | warden | "is `make check` an outlier vs node median?" |

Honesty rules: gaps with no timestamp evidence are emitted as
`unmeasured`, never zero-filled; LLM time is *inferred* from
gaps (label it `inferred`), tool time is *observed*. A run with
no usable clocks produces no trace, plus a named gap.

Deliberately not: no live/streaming profiling, no token-cost
model (later), no trace UI of our own — Perfetto is the UI.

## Blockers

- **Depends on graph 1** (tape scraper + `tool_calls` table).
  Tape-only fallback was considered and rejected: two parsers.
- **Clock quality.** If tape/tool timestamps stay sparse, most
  intervals are inferred. May need a bp3 hook that stamps tool
  boundaries deliberately — decide at thaw from real traces.
- **Run correlation across cycles:** flame chart wants
  node→cycles stacked; the trace `pid/tid` mapping above is a
  sketch, re-decide against one real quest's data.

## Promotion trigger

Thaw after graph 1 lands and one real quest's runs are in the
DB; first acceptance is a trace the owner opens in Perfetto
and recognizes ("yes, that's where the time went").
