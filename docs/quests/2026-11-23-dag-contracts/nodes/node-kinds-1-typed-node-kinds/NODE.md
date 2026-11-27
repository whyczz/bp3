---
node: kinds.1
---

# kinds.1 - typed-node-kinds

TL;DR
Replace `Store.plan_knobs_from_text`'s 3-knob substring parser with five explicit typed node flavors (`Code | Direct | Research | Explore | Human_gate`), expose `--kind` at node creation, add the `approve` edge for `Human_gate` (`BP3_DECIDER=human` -> `decider: "human"`, or `BP3_DECIDER=human-approved-llm-yolo` -> `decider: "human-approved-llm-yolo"` surfaced in `bp3 q r` `yolo_approvals`; no extra CLI flag), and add lightweight `E_PROTECTED_FILE` (+ `--allow-protected`) enforcement on `handoff`.

## Acceptance gates

Design trace:

```text
# 1. Code node (default) + protected-file lock
$ bp3 q demo c c1   # --kind defaults to code
$ bp3 q demo n c1 e handoff --commit $C_TOUCHES_GRADING --reason "sneaky"
-> exit 1, E_PROTECTED_FILE naming "GRADING.md"
$ bp3 q demo n c1 e handoff --commit $C_TOUCHES_GRADING --allow-protected --reason "intentional rule update"
-> exit 0, state: "handed_off"

# 2. Direct node (fast verified commit, no AI grade)
$ bp3 q demo c d1 --kind direct
$ bp3 q demo n d1 e handoff --commit $C_SMALL_FIX --reason "verified"
-> exit 0, state: "landed", fin: "node_fin"

# 3. Human-gate node (interactive human approval OR honest BP3_DECIDER=human-approved-llm-yolo)
$ bp3 q demo c g1 --kind human-gate --depends-on d1
$ bp3 q demo n g1 e approve --reason "pick B"
-> exit 1, E_HUMAN_REQUIRED
$ BP3_DECIDER=human bp3 q demo n g1 e approve --reason "pick B"
-> exit 0, state: "landed", fin: "node_fin", decider: "human"
$ bp3 q demo c g2 --kind human-gate --depends-on g1
$ BP3_DECIDER=human-approved-llm-yolo bp3 q demo n g2 e approve --reason "chose B: lower risk, reversible"
-> exit 0, state: "landed", fin: "node_fin", decider: "human-approved-llm-yolo"
$ bp3 q r demo | jq '.yolo_approvals'
-> [{"node": "g2", "decider": "human-approved-llm-yolo", "reason": "chose B: lower risk, reversible", ...}]
# Strictly scoped: release / resume / delete-blocked reject human-approved-llm-yolo:
$ BP3_DECIDER=human-approved-llm-yolo bp3 release demo
-> exit 1, E_HUMAN_REQUIRED
```

Runnable goal block:
- **objective:** Support `code`, `direct`, `research`, `explore`, and `human-gate` as first-class DAG node kinds with clean legal-edge tables, `Human_gate` approval via `BP3_DECIDER` (`human` + `human-approved-llm-yolo` with `yolo_approvals` rollup, strictly scoped away from `bp3 release`/`resume`/`delete`), `E_PROTECTED_FILE`, and full legacy ledger compatibility.
- **prove by:** Unit tests in `test/unit/test_store.ml` for all 5 `node_kind` variants + legacy ledger default (`Code`) + `BP3_DECIDER` parsing (`human` vs `human-approved-llm-yolo` vs unset) + protected-file helper (including rename old/new paths) + fixture tests exercising `Code`, `Direct`, `Human_gate` (both `BP3_DECIDER=human` and `BP3_DECIDER=human-approved-llm-yolo`, plus confirming `release`/`resume` still reject `human-approved-llm-yolo`), and `E_PROTECTED_FILE` + `make check-full`.
- **done when:** `make check-full` exits `0`, `Store.plan_knobs_from_text` no longer relies on brittle `contains_sub` heuristics, `Human_gate` never trips Warden `human_steer`, `yolo_approvals` surfaces every `human-approved-llm-yolo` approval in `bp3 q r`, and `E_PROTECTED_FILE` blocks undeclared edits to protected paths.

## Diagram

```text
Code       : todo --handoff(clean+protected+ancestry)--> handed_off --grade(ship)--> landed
Direct     : todo --handoff(clean+protected+ancestry)--> landed
Human_gate : todo --approve(BP3_DECIDER=human | human-approved-llm-yolo)--> landed   (commit = None)
Research   : todo --handoff(docs-only, wired in research.1)--> landed
Explore    : todo --[iterate]*--handoff(docs-only+outcome, wired in research.1)--> landed
```

## Pseudocode

```python
PROTECTED = ["GRADING.md", "CONSTRAINTS.md", "scripts/receipt", "scripts/red-first"]

def check_protected(quest, node, allow_protected, changed_paths):
    if allow_protected:
        return
    locked = set(PROTECTED + [f"docs/quests/{quest}/nodes/{node}/NODE.md"])
    bad = [p for p in changed_paths if p in locked]
    if bad:
        raise E_PROTECTED_FILE(bad)

def legal_edges(kind, state):
    if state in ("landed", "deleted"): return []
    if state == "blocked": return ["resume", "delete"]
    if kind == "human-gate":
        return ["approve", "block", "delete"] if state == "todo" else []
    if kind == "explore":
        return ["iterate", "handoff", "block", "delete"] if state == "todo" else []
    if kind in ("direct", "research"):
        return ["handoff", "block", "delete"] if state == "todo" else []
    # code
    return {"todo": ["handoff", "block", "delete"],
            "handed_off": ["grade", "block", "delete"],
            "approved": ["land", "block", "delete"]}[state]
```

## Tables

| Field | Value |
|---|---|
| Intent | Give quests 5 native node flavors and deterministic `E_PROTECTED_FILE` locks without carrying a glob permissions engine. |
| Lane | standard |
| Output | `node_kind` type + clean plan parser in `src/quest/store.ml`, edge dispatch + `E_PROTECTED_FILE` in `src/quest/main.ml`, `kind` display in `src/quest/render.ml`, `E_PROTECTED_FILE` in `src/quest/names.ml`, unit + fixture tests. |
| Acceptance | Fails today: `--kind` is rejected as `E_USAGE`, `approve` edge does not exist, `handoff` accepts commits modifying `GRADING.md`, and `Store.plan_knobs_from_text` uses `contains_sub` for 3 booleans. |
| Depends on | `2026-11-23-dag-fsm-v2` |

## Prose

`CONTEXT.md:52` notes humans decide *"which of several valid options should we choose."* Today, a mid-quest human decision forces an agent to abuse `block` on a coding node (which trips Warden's `human_steer` plug and stalls the node's own cycle count). Naming the flavor `human-gate` avoids colliding with "Acceptance gates" and "`make check-full` gate".

Edge cases:
- **Legacy ledgers without `node_kind`:** fold cleanly to `Code` (or `Direct` when `quest_type = "direct"`), preserving 100% backward compatibility.
- **Renames/deletions in `git diff-tree`:** check *both* old and new paths on rename (`R`) so moving a protected file cannot bypass `E_PROTECTED_FILE`.
- **Interaction with `dag-fsm-v2` git ancestry:** `Human_gate` lands with `commit = None`, so downstream `Code` nodes skip the commit-less gate cleanly without `E_MISSING_ANCESTOR`.
- **Warden interaction:** `Human_gate` approvals are intentional human touchpoints, NOT mid-build `human_steer` anomalies — verify `bp3 warden` does not falsely flag a `Human_gate` approval.
