---
date: 2026-11-23
quest: ../../QUEST.md
node: plugs.1
status: proposed
---

# plugs.1 - warden-engine: pure Elixir-plug rule pipeline in `src/warden/`

## TL;DR

Implement `src/warden/warden.ml` (in a dedicated `bp3_warden` dune library under `src/warden/dune`, one-way dependency on `bp3_quest`) as a pure, composable two-layer plug pipeline (`evidence -> finding list`) over already-parsed ledger edges, `Metrics.sample` lists, `QUEST.md` active statuses, post-land commits, desk status, and joined `Tx` session traces — zero I/O, zero SQLite, zero side effects. Ships **12 deterministic plugs** (**8 Layer-1 git/repo plugs**: `multi_active_quest`, `cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`, `coverage_gap`, `desk_leak`, `post_land_bugfix`; **4 Layer-2 session-trace plugs**: `tool_retry_loop`, `full_gate_in_author`, harness-aware `context_bloat`, author-window-scoped `human_steer`), adds `s_user_steps` across `Tx`/`Agy_tx`/`Claude_tx`/`Pi_tx` and `Layout.feedback_file = "FEEDBACK.md"`, and proves every plug + `QCheck2` invariants in `test/unit/test_warden.ml`.

## Acceptance gates

Observed today:

```text
$ ls src/warden/warden.ml
ls: src/warden/warden.ml: No such file or directory
```

Design trace:

```text
Warden.run evidence   # 8 Layer-1 plugs + 4 Layer-2 plugs (when evidence.traces <> [])
  -> returns deterministic list of findings, sorted by (severity desc, layer, quest, node, cycle, rule)
  -> each finding carries { rule; layer; severity; quest; node; cycle; observed; threshold; evidence_ref; summary }
  -> Layer-2 findings cite exact transcript path + step/line (e.g. "tx:<path>#step:14")
  -> evidence.traces = [] (no local transcripts or --no-sessions) -> runs Layer 1 cleanly with zero error
  -> clean node (1 cycle, grade <= 180s, no retries, <=1 check-full, context within harness limit, 0 mid-node steers, 0 post-land fixes) -> []
```

```yaml
objective: provide a pure, testable two-layer deterministic plug pipeline in src/warden/ detecting 8 git/repo and 4 session-trace waste classes
prove by:
  - test/unit/test_warden.ml: positive + negative known cases for all 12 plugs, harness-aware context_bloat (150k claude/pi vs 400k agy), grade_inversion (>180s & >1.5x), author-window human_steer, post_land_bugfix, multi_active_quest, graceful empty-traces case, clean-quest -> [], JSON + table formatting, and QCheck2 property laws (deterministic sort order & counts.total == List.length findings)
  - test/unit/test_agy_tx.ml + test/unit/test_metrics.ml: s_user_steps populated across Agy_tx, Claude_tx, Pi_tx
  - make check-full
done when: test_warden.ml, test_agy_tx.ml, test_metrics.ml pass in dune test and make check-full passes
```

## Diagram

```text
evidence { repo_active_quests, quests: [{ quest, nodes, open_desks, post_land_commits, traces }] }
   │
   ├─ Layer 1 (git/repo — always runs, 8 plugs):
   │   ├─ 1. multi_active_quest   (> 1 docs/quests/*/QUEST.md has status: active)
   │   ├─ 2. cycle_outlier        (max_cycle > 2 || any grade.wall_s > 300s)
   │   ├─ 3. minor_only_bounce    (needs_fix reason has "[minor]" and no "[critical]"/"[major]")
   │   ├─ 4. vacuous_test_bounce  (needs_fix reason matches "can't fail" | "stays green" | "mutant")
   │   ├─ 5. grade_inversion      (sum grade.wall_s > 180s && > 1.5x sum author.wall_s, or grade.tokens_out > author.tokens_out)
   │   ├─ 6. coverage_gap         (grade/handoff edges > 0 with 0 samples; skips legacy pre-metrics quests)
   │   ├─ 7. desk_leak            (grade-* desk still open for landed node, or >=3 identical E_* refusals)
   │   └─ 8. post_land_bugfix     (> 0 non-status commits after final node_fin commit)
   │
   └─ Layer 2 (session-trace — runs automatically when traces <> [], 4 plugs):
       ├─ 9.  tool_retry_loop     (>= 3 consecutive failing tool_events or >= 3 identical failing cmd_head)
       ├─ 10. full_gate_in_author (author window ran `make check-full` > 1x before handoff)
       ├─ 11. context_bloat       (context_end > 150k claude/pi or > 400k agy, or turns > 30)
       └─ 12. human_steer         (> 0 mid-node USER_INPUT inside [prev_edge_ts..handoff_ts] excluding kickoff, or Layer-1 block edge)
   │
   ▼
finding list -> JSON { ok, scope, quests, sessions_scanned, findings, counts } / table rows
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
    cycle: int          # 0 for node/quest/repo-wide findings
    observed: str       # e.g. "4 cycles", "420k tok", "2 commits"
    threshold: str      # e.g. "> 2 cycles", "> 400k tok", "> 0 commits"
    evidence_ref: str   # "ledger:<node>:c2" | "tx:<path>#step:14" | "git:<sha7>" | "repo:QUEST.md"
    summary: str

def run(evidence):
    out = [f for plug in LAYER1_PLUGS for f in plug(evidence)]
    if any(q.traces for q in evidence.quests):
        out.extend(f for plug in LAYER2_PLUGS for f in plug(evidence))
    return sort_findings(out)
```

## Tables

| Field | Value |
|---|---|
| Intent | implement the pure deterministic Warden library in `src/warden/` without coupling to git/filesystem I/O |
| Lane | standard |
| Output | `src/warden/dune` (new, `bp3_warden`), `src/warden/warden.ml` (new), `src/quest/tx.ml`, `src/quest/agy_tx.ml`, `src/quest/claude_tx.ml`, `src/quest/pi_tx.ml`, `src/quest/layout.ml` (`feedback_file`), `test/unit/test_warden.ml` (new), `test/unit/test_agy_tx.ml`, `test/unit/test_metrics.ml`, `test/unit/dune` |
| Acceptance | fails today (`src/warden/` does not exist); passes when `test_warden.ml` (known + `QCheck2`) and `make check-full` pass |
| Depends on | none |
| Must not touch | `skills/*`, `bin/bp3`, `src/quest/main.ml`, `CONSTRAINTS.md` |

## Prose

- **Dedicated `bp3_warden` library (`src/warden/dune`):** enforces a clean one-way dependency (`bp3_warden` -> `bp3_quest`), automatically allowed as an internal library by `scripts/check-constraints:115`.
- **Precision-first calibration (settled in red-ink):**
  - `context_bloat` is harness-aware (`>150k` Claude/Pi 200k window vs `>400k` `agy` 1M window, or `turns > 30`).
  - `grade_inversion` uses a `>180s` & `>1.5x` author-wall floor so quick 2-minute grades don't false-fire.
  - `human_steer` scopes strictly to `USER_INPUT` turns inside each node's `[prev_edge_ts .. handoff_ts]` author window (excluding the kickoff prompt) plus Layer-1 `block` edges, so post-quest chat never false-fires.
- **Test split:** Known cases (all 12 plugs positive/negative + edge cases) AND `QCheck2` property-based laws (deterministic sort order, `counts.total == List.length findings`).
