---
status: frozen
date: 2026-11-17
promoted: null
---

# Tape scraper → SQLite FTS5 (session miner, graph 1 of 3)

## Context

Frozen 2026-11-17 during the graph-engine quest
(2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines).
That quest proved the pain by hand: conductors grepped raw
`tape.log` files, workflow children hand-copied 513-line command
output into JSON returns, and nobody could ask "which runs ate
`E_AMBIGUOUS`?" without archaeology. Follow-ups: profiler
([2026-11-17-run-profiler-chrome-trace.md](2026-11-17-run-profiler-chrome-trace.md))
reads this DB; the warden
([2026-11-17-warden-plug-rules.md](2026-11-17-warden-plug-rules.md))
rules over it. Not harness session JSONL: the older
harness-log miner idea was retired 2026-11-17 (owner cleanup
B) and its warden catalog moved into the warden entry; this
entry is bp3's own tapes only.
Derived data only: a scraper never writes ledger lines or state.

## Sketch

```text
nodes/*/runs/<run-id>/tape.log ──┐
nodes/*/ledger.jsonl ────────────┼─> scrape ─> .git/bp3/miner.sqlite ─> FTS5 / SQL queries
.git/bp3/<run-id>-validations.log┘        (derived, rebuildable, gitignored)
```

| Table | Key columns | Answers |
|---|---|---|
| `runs` | `run_id` PK, graph, node, edge, cycle, harness, model, bp3_version, commit, verdict, tape_path | "all grade runs for followup.3" |
| `tape_lines` | run_id, line_no, ts (nullable), kind, text | raw evidence, line-addressable |
| `tape_fts` (FTS5) | text ← tape_lines, prefix-indexed | "runs mentioning `E_AMBIGUOUS`" |
| `tool_calls` | run_id, tool, cmd_hash, started, ended, exit | profiler input (graph 2) |
| `ledger_facts` | graph, node, edge, ts, cycle, commit | join tape ↔ truth; gaps = report |

Indexes: `(graph, node)`, `(graph, node, cycle)`, `commit`,
`tool_calls(tool, exit)`, `runs(started_at)`. Identity is
derived from path + run-id (`<ts>-<edge>-<harness>-<model>-c<n>`),
never parsed out of tape prose. Re-scrape is idempotent:
`miner.sqlite` deletes and rebuilds clean.

Deliberately not: no harness session logs (older entry's job),
no fact repair, no state writes, no UI.

## Blockers

- **Tape timestamps are sparse.** Some lines carry no clock;
  ordering falls back to line_no. Durations may stay `unmeasured`.
- **Tape format is verbatim, unversioned.** Scraper must fail
  loud on shapes it cannot split, never guess-parse into facts.
- **DB home undecided:** `.git/bp3/` (shared across worktrees,
  derived) vs a docs home. Leaning `.git/bp3/`; decide at thaw.
- **Scale unknown.** FTS5 is fine until tape volume proves
  otherwise; no chunking/embeddings in graph 1.

## Promotion trigger

Thaw when the graph-engine quest lands and someone needs a
second cross-run question answered by hand-grep — or when the
profiler (graph 2) is thawed, whichever comes first. This DB
is graph 2's input contract, so it thaws first.
