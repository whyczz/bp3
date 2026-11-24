---
node: fsm.1
---

# fsm.1 - collapse-verify-and-auto-land

TL;DR
Simplify the default per-node FSM from 3 happy-path edges (`handoff -> grade --verify-verdict -> land`) to 2 (`handoff -> grade`), auto-landing on `grade --verdict ship` when `land: auto` (the new default), retiring standalone `verify` writes while keeping `Store.fold_ledger` 100% backward-compatible with pre-v2 ledgers.

## Acceptance gates

Design trace:

```text
# Default plan (land: auto)
$ bp3 q demo c n1
$ bp3 q demo n n1 e handoff --commit $C1 --reason "ready"
-> {"ok": true, "state": "handed_off", "legal_edges": ["grade", "block", "delete"]}
$ bp3 q demo n n1 e grade --verdict ship --reason "clean"
-> {"ok": true, "state": "landed", "fin": "node_fin", "legal_edges": []}

# Manual-land plan (land: manual)
$ bp3 q demo-m c n1 --type manual
$ bp3 q demo-m n n1 e handoff --commit $C1 --reason "ready"
$ bp3 q demo-m n n1 e grade --verdict ship --reason "clean"
-> {"ok": true, "state": "approved", "legal_edges": ["land", "block", "delete"]}
$ bp3 q demo-m n n1 e land --reason "ship"
-> {"ok": true, "state": "landed", "fin": "node_fin", "legal_edges": []}

# Standalone verify refused cleanly; legacy ledger still folds
$ bp3 q demo n n1 e verify --verdict pass --reason "old"
-> exit 1, E_EDGE_RETIRED (or E_USAGE per Open question 1)
```

Runnable goal block:
- **objective:** Make `grade --verdict ship` land directly under `land: auto` (default) without breaking `land: manual` plans or historical ledger folds.
- **prove by:** `dune test` (`test/unit/test_store.ml` + FSM unit tests covering `land: auto`, `land: manual`, `--verify-verdict` compat, retired `verify`, and historical `verify`/`approved` ledgers) + fixture test + `make check-full`.
- **done when:** `make check-full` exits `0`, default plans land in 2 edges (`handoff`, `grade`), `legal_edges "handed_off"` omits `"verify"`, and all historical ledgers fold identically.

## Diagram

```text
land: auto (default)
  todo --handoff--> handed_off --grade(ship)--> landed (node_fin, quest ref moved)
                         |
                 grade(needs_fix) --> todo (cycle+1) or blocked (at cap)

land: manual (opt-in)
  todo --handoff--> handed_off --grade(ship)--> approved --land--> landed
```

## Pseudocode

```python
def apply_grade(node_state, knobs, verdict, verify_verdict, mechanical):
    if verdict == "needs_fix" or verify_verdict == "fail":
        if mechanical or node_state.cycle < knobs.max_cycles:
            return transition("todo", cycle=node_state.cycle + 1)
        return transition("blocked", cycle=node_state.cycle)
    # verdict == "ship"
    if knobs.auto_land:
        return land_node_and_advance_quest_ref(node_state)
    return transition("approved", cycle=node_state.cycle)
```

## Tables

| Field | Value |
|---|---|
| Intent | Remove the redundant `verify` edge and 1-second `approved` hop on default plans while keeping legacy reads and `land: manual` intact. |
| Lane | standard |
| Output | Updated `src/quest/store.ml`, `src/quest/main.ml`, `src/quest/render.ml`, `plans/default.yaml`, `plans/direct.yaml`, and unit/fixture tests. |
| Acceptance | Fails today: `grade --verdict ship` without `--verify-verdict pass` stays in `handed_off`, and with `--verify-verdict pass` stops in `approved` instead of `landed`. |
| Depends on | none (after `codebase-diet`) |

## Prose

In `induct-inline`, `scripts/receipt` runs as part of the cold grade, so nobody invokes a separate `verify` edge anymore and `approved` is always immediately followed by `land`. Keeping `auto_land: bool` (parsed from `land: auto | manual`, defaulting to `true`) lets default quests cut a full CLI write + CAS round-trip per node while preserving an opt-in manual `approved -> land` step for high-ceremony plans.

Edge cases:
- `plans/direct.yaml` (`grade.required: false`, `land: auto`): `handoff` transitions straight to `landed` (advancing quest ref) instead of parking in `approved`.
- `--verify-verdict fail` passed with `--verdict ship` (deprecated compat): still treated as negative (`needs_fix` path) so callers never accidentally ship on a failed receipt.
- `merge-tree` conflict during auto-land on per-node refs: rolls back cleanly to `todo` with `facts.land_conflict: true`, identical to today's `main.ml:333-341`.
- Historical ledgers containing `verify` lines and `approved` states continue folding cleanly in `Store.fold_ledger`.
