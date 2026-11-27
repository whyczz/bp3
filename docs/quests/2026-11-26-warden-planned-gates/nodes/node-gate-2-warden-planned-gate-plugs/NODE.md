---
node: gate.2
slug: warden-planned-gate-plugs
kind: code
lane: standard
status: proposed
depends_on:
  - gate.1 - planned-block-flag
---

# gate.2 - warden-planned-gate-plugs

TL;DR
Thread `ne_kind` and `le_planned` into `Warden`, compute pure `planned_block_windows` from node ledgers, suppress Layer-1 and Layer-2 `human_steer` findings for `--kind human-gate` nodes and planned `[block_ts, resume_ts]` intervals while keeping unplanned blocks, cycle-cap escalations, and out-of-window steers as `Major human_steer`, and expose an additive `planned_gates` count in `bp3 warden` JSON and table output.

## Acceptance gates

Design trace:

```text
# 1. Planned block + check-ins inside [block_ts, resume_ts] -> 0 human_steer, planned_gates = 1
ledger: create(t=10) -> block --planned(t=100) -> resume(t=300) -> handoff(t=400) -> grade ship -> land
author trace: jt_user_steps = [(step=5, t=150), (step=8, t=250)]
Warden.run -> findings = [], planned_gates = 1

# 2. Same planned block, plus one steer AFTER resume at t=350 -> 1 Major human_steer (session)
author trace: jt_user_steps = [(step=5, t=150), (step=12, t=350)]
Warden.run -> findings = [{rule:"human_steer", layer:Session, severity:Major, observed:"1 mid-node user inputs", evidence_ref:"tx:...#step:12"}], planned_gates = 1

# 3. Unplanned block (planned=false) or cycle-cap escalation (to="blocked") -> Major human_steer (git)
Warden.run -> findings = [{rule:"human_steer", layer:Git, severity:Major, ...}], planned_gates = 0

# 4. --kind human-gate node with user input + approve -> 0 human_steer, planned_gates = 1
Warden.run -> findings = [], planned_gates = 1
```

Runnable goal block:
- **objective:** Separate planned owner gates (`--kind human-gate` and `e block --planned`) from unplanned `Major human_steer` across both Warden layers, purely and deterministically.
- **prove by:** Pure unit + QCheck2 tests in `test/unit/test_warden.ml` and end-to-end CLI fixture tests in `test/warden.sh`.
- **done when:** `make check-full` passes with every positive, negative, boundary, and property test green.

## Diagram

```text
Warden_io.load_quest
  |-- Store.fold_node -> ne_kind ("code" | ... | "human-gate")
  |-- entries_of_text -> le_planned (bool, default false)
  v
Warden.run (pure, zero I/O)
  |-- planned_gates_count(ev) -> int (human-gate approves + planned blocks)
  |-- plug_human_steer_block:
  |     ignore if ne_kind = "human-gate" || (le_edge = "block" && le_planned)
  |     else fire Major human_steer on non-refused block / to = "blocked"
  |-- plug_human_steer_session:
  |     ignore if node.ne_kind = "human-gate"
  |     windows = planned_block_windows(node.ne_entries)  (* [block_ts, resume_ts] *)
  |     unplanned = filter (ts not in any [lo, hi]) tr.jt_user_steps
  |     fire Major human_steer iff unplanned <> []
  v
JSON: {..., "planned_gates": N, "findings": [...]}
Table: header shows planned_gates when N > 0
```

## Pseudocode

```python
@dataclass(frozen=True)
class LedgerEntry:
    ts: str
    edge: str
    to: str
    cycle: int
    reason: str
    refused: bool
    planned: bool = False          # parsed from JSON "planned", default False

def planned_block_windows(entries: list[LedgerEntry]) -> list[tuple[float, float]]:
    windows: list[tuple[float, float]] = []
    open_start: float | None = None
    for e in entries:
        if e.refused:
            continue
        t = parse_seconds(e.ts)
        if e.edge == "block" and e.planned and t is not None:
            if open_start is None:
                open_start = t
        elif open_start is not None and e.edge in ("resume", "land", "delete") and t is not None:
            windows.append((open_start, max(open_start, t)))
            open_start = None
    if open_start is not None:
        windows.append((open_start, float("inf")))
    return windows

def in_any_window(ts: float, windows: list[tuple[float, float]]) -> bool:
    return any(lo <= ts <= hi for lo, hi in windows)
```

## Fields

| Field | Value |
|---|---|
| Intent | Make Warden Layer 1 and Layer 2 planned-gate-aware and report `planned_gates` |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/warden/warden.ml`, `src/warden/warden_io.ml`, `test/unit/test_warden.ml`, `test/warden.sh` |
| Acceptance | Fails today (`plug_human_steer_block` and `plug_human_steer_session` flag planned blocks and `human-gate` nodes); passes when all 4 design-trace cases and QCheck2 law hold |
| Depends on | `gate.1 - planned-block-flag` |

## Prose & edge cases

- **Still-blocked planned node:** If a node took `e block --planned` and has not resumed yet, `planned_block_windows` yields `(block_ts, Float.infinity)` so operational check-ins while waiting on the overnight run are suppressed.
- **Cycle-cap escalation:** A `grade` edge that hits `max_cycles` sets `to = "blocked"` with `edge = "grade"` and `planned = false`; `plug_human_steer_block` MUST still fire `Major human_steer` on it.
- **Multiple planned blocks on one node:** Each `block --planned -> resume` pair produces its own disjoint `[lo, hi]` interval; `USER_INPUT` between `resume_1` and `block_2` is outside both intervals and still fires `Major human_steer`.
- **Legacy ledgers & missing traces:** Entries without `"planned"` default to `le_planned = false`; nodes without `node_kind` fold to `"code"` via `Store.fold_node`, preserving 100% backward compatibility.
- **Evidence pointer accuracy:** When a trace has both in-window check-ins and an out-of-window steer, `plug_human_steer_session` MUST report the count and `evidence_ref` (`tx:<path>#step:<first_unplanned_step>`) of the *unplanned* steps only.
- **Tests:**
  - *Known cases:* (1) planned block + in-window `USER_INPUT` -> `0` findings, `planned_gates = 1`; (2) planned block + post-resume `USER_INPUT` -> `Major human_steer` citing the post-resume step; (3) unplanned block -> `Major human_steer` (Layer 1) and in-block `USER_INPUT` still fires Layer 2; (4) cycle-cap `grade -> blocked` escalation -> `Major human_steer`; (5) `--kind human-gate` node with `approve` + `USER_INPUT` -> `0` findings, `planned_gates = 1`; (6) still-blocked planned node -> `0` findings; (7) CLI fixture in `test/warden.sh` running `bp3 warden --format json` and `--format table`.
  - *Property-based (QCheck2):* Generate arbitrary sorted planned `[lo, hi]` block intervals and random `USER_INPUT` timestamps; assert that `plug_human_steer_session` fires iff at least one timestamp lies strictly outside every `[lo, hi]`, and that its reported count equals the exact number of out-of-window timestamps.
