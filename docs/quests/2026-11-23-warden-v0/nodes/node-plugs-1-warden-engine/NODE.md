---
date: 2026-11-23
quest: ../../QUEST.md
node: plugs.1
status: proposed
---

# plugs.1 - warden-engine: pure Elixir-plug rule pipeline in OCaml

## TL;DR

Implement `src/quest/warden.ml` as a pure, composable two-layer plug pipeline (`evidence -> finding list`) over already-parsed ledger edges, `Metrics.sample` lists, desk status, and joined `Tx` session traces — zero I/O, zero SQLite, zero side effects. Ships **9 deterministic plugs** (**6 Layer-1 git plugs**: `cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`, `coverage_gap`, `desk_leak`; **3 Layer-2 session-trace plugs**: `tool_retry_loop`, `full_gate_in_author`, `context_bloat`) with unit tests covering every plug.

## Acceptance gates

Observed today:

```text
$ ls src/quest/warden.ml
ls: src/quest/warden.ml: No such file or directory
```

Design trace:

```text
Warden.run evidence   # 6 Layer-1 plugs + 3 Layer-2 plugs (when evidence.traces <> [])
  -> returns deterministic list of findings, sorted by (severity desc, layer, node, cycle, rule)
  -> each finding carries { rule; layer; severity; quest; node; cycle; evidence_ref; summary }
  -> Layer-2 findings cite exact transcript path + step/line (e.g. "tx:<path>#step:14")
  -> evidence.traces = [] (no local transcripts or --no-sessions) -> runs Layer 1 cleanly with zero error
  -> clean node (1 cycle, grade <= author, no retries, no mid-cycle check-full spam, context <= 150k) -> []
```

```yaml
objective: provide a pure, testable two-layer deterministic plug pipeline detecting 6 git-level and 3 session-trace waste classes
prove by:
  - test/unit/test_warden.ml: positive + negative unit cases for all 9 plugs (cycle_outlier, minor_only_bounce, vacuous_test_bounce, grade_inversion, coverage_gap, desk_leak, tool_retry_loop, full_gate_in_author, context_bloat), graceful empty-traces case, clean-quest case returning [], and JSON serialization round-trip
  - make check-full
done when: test_warden.ml passes in dune test and make check-full passes
```

## Diagram

```text
evidence { quest, nodes: [(name, edges, samples, raw_ledger_lines)], open_desks, traces: [Tx.joined_trace] }
   │
   ├─ Layer 1 (git-only — always runs):
   │   ├─ plug 1: cycle_outlier        (max_cycle > 2 || any grade.wall_s > 300s)
   │   ├─ plug 2: minor_only_bounce    (needs_fix reason has "[minor]" and no "[critical]"/"[major]")
   │   ├─ plug 3: vacuous_test_bounce  (needs_fix reason matches "can't fail" | "stays green" | "mutant")
   │   ├─ plug 4: grade_inversion      (sum grade.wall_s > sum author.wall_s && > 120s, or grade.tokens_out > author.tokens_out)
   │   ├─ plug 5: coverage_gap         (grade edges > 0 with 0 grade.* samples, or handoffs > 0 with 0 author.* samples)
   │   └─ plug 6: desk_leak            (grade-* desk still open for landed node, or >=3 identical E_* refusals in raw ledger)
   │
   └─ Layer 2 (session-trace — runs automatically when traces <> []):
       ├─ plug 7: tool_retry_loop      (>=3 consecutive failed tool_events or >=3 identical failing cmd_head in one window)
       ├─ plug 8: full_gate_in_author  (author window ran `make check-full` > 1x before handoff — Warden catalog row #8)
       └─ plug 9: context_bloat        (context_end > 150_000 or turns > 30 on a micro/standard node)
   │
   ▼
finding list -> JSON { findings, counts } / table rows
```

## Pseudocode

```python
@dataclass
class Finding:
    rule: str
    layer: str          # "git" | "session"
    severity: str       # "major" | "minor"
    quest: str
    node: str
    cycle: int          # 0 for node/quest-wide findings
    evidence_ref: str   # e.g. "ledger:node-brief-2:c3" or "tx:/path/transcript.jsonl#step:14"
    summary: str

LAYER1_PLUGS = [cycle_outlier, minor_only_bounce, vacuous_test_bounce,
                grade_inversion, coverage_gap, desk_leak]
LAYER2_PLUGS = [tool_retry_loop, full_gate_in_author, context_bloat]

def run(evidence):
    out = [f for plug in LAYER1_PLUGS for f in plug(evidence)]
    if evidence.traces:
        out.extend(f for plug in LAYER2_PLUGS for f in plug(evidence))
    return sort_findings(out)
```

## Tables

| Field | Value |
|---|---|
| Intent | implement the pure deterministic Warden rules without coupling to git/filesystem I/O |
| Lane | standard |
| Output | `src/quest/warden.ml` (new), `test/unit/test_warden.ml` (new), `test/unit/dune` |
| Acceptance | fails today (`src/quest/warden.ml` does not exist); passes when `test_warden.ml` and `make check-full` pass |
| Depends on | none |
| Must not touch | `skills/*`, `bin/bp3`, `src/quest/main.ml`, `CONSTRAINTS.md` |

## Prose

Design choices:
- **Pure core, I/O at the edge:** `Warden` takes already-loaded `Metrics.edge list`, `Metrics.sample list`, raw ledger lines (for `E_*` refusals, since `Metrics.edges_of_text` filters to transitions), and open desk names. That makes every plug fast (<1ms) and trivially unit-testable in `dune test`.
- **Precision-first heuristics:**
  - `minor_only_bounce` requires explicit `[minor]` AND absence of `[critical]` and `[major]` (case-insensitive) so untagged legacy reasons never false-fire.
  - `grade_inversion` guards with a minimum `grade_wall_s > 120s` floor so a 10s trivial edit with a 30s grade doesn't spam noise.
  - `coverage_gap` skips quests landed before `metrics.jsonl` existed (or tags `severity: "minor"` when zero samples exist across the whole quest) so historical pre-metrics quests don't drown recent ones under `--all-landed`.
- **Extensible plug list:** adding a 7th rule later is adding one pure function to `Warden.all_plugs` + one unit test case.
