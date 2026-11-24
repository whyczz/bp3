---
node: kinds.1
---

# kinds.1 - typed-node-kinds

TL;DR
Replace `Store.plan_knobs_from_text`'s 3-knob substring parser with four explicit typed node kinds (`Code | Direct | Spike | Gate`), exposed via `--kind code|direct|spike|gate` at node creation and rendered in `bp3 q r` / `diagram`.

## Acceptance gates

Design trace:

```text
# 1. Spike node (docs-only, never lands code)
$ bp3 q demo c sp1 --kind spike
$ bp3 q demo n sp1 e handoff --commit $C_TOUCHES_SRC --reason "try code"
-> exit 1, E_SPIKE_CODE_TOUCHED
$ bp3 q demo n sp1 e handoff --commit $C_DOCS_ONLY --reason "findings recorded"
-> exit 0, state: "landed", fin: "node_fin"

# 2. Gate node (human checkpoint in the DAG)
$ bp3 q demo c g1 --kind gate --depends-on sp1
$ bp3 q demo n g1 e approve --reason "pick B"
-> exit 1, E_HUMAN_REQUIRED
$ BP3_DECIDER=human bp3 q demo n g1 e approve --reason "pick B"
-> exit 0, state: "landed", fin: "node_fin"

# 3. Direct node (fast watched commit, no AI grade)
$ bp3 q demo c d1 --kind direct --depends-on g1
$ bp3 q demo n d1 e handoff --commit $C_SMALL_FIX --reason "verified"
-> exit 0, state: "landed", fin: "node_fin"

# 4. Code node (default: handoff -> handed_off -> cold grade -> landed)
$ bp3 q demo c c1 --depends-on d1   # --kind defaults to code
```

Runnable goal block:
- **objective:** Support `code`, `direct`, `spike`, and `gate` as first-class DAG node kinds with clean legal-edge tables and ledger compatibility.
- **prove by:** Unit tests in `test/unit/test_store.ml` for all 4 `node_kind` variants + legacy ledger default (`Code`) + fixture tests exercising `Spike`, `Gate`, `Direct`, and `Code` in one DAG + `make check-full`.
- **done when:** `make check-full` exits `0`, `Store.plan_knobs_from_text` no longer relies on brittle `contains_sub` heuristics, and all 4 node kinds work end-to-end.

## Diagram

```text
Code   : todo --handoff(clean+owns+ancestry)--> handed_off --grade(ship)--> landed
Direct : todo --handoff(clean+owns+ancestry)--> landed
Spike  : todo --handoff(docs/** only)---------> landed
Gate   : todo --approve(BP3_DECIDER=human)----> landed   (commit = None)
```

## Pseudocode

```python
def legal_edges(kind, state):
    if state in ("landed", "deleted"): return []
    if state == "blocked": return ["resume", "delete"]
    if kind == "gate":
        return ["approve", "block", "delete"] if state == "todo" else []
    if kind in ("direct", "spike"):
        return ["handoff", "block", "delete"] if state == "todo" else []
    # code
    return {"todo": ["handoff", "block", "delete"],
            "handed_off": ["grade", "block", "delete"],
            "approved": ["land", "block", "delete"]}[state]
```

## Tables

| Field | Value |
|---|---|
| Intent | Give quests native `Code`, `Direct`, `Spike`, and `Gate` nodes so throwaway experiments and human decisions don't get shoehorned into code commits or fake `block`/`resume` cycles. |
| Lane | standard |
| Output | `node_kind` type + clean plan parser in `src/quest/store.ml`, edge dispatch in `src/quest/main.ml`, `kind` display in `src/quest/render.ml`, `E_SPIKE_CODE_TOUCHED` in `src/quest/names.ml`, unit + fixture tests. |
| Acceptance | Fails today: `--kind` is rejected as `E_USAGE`, `approve` edge does not exist, and `Store.plan_knobs_from_text` uses `contains_sub` for 3 booleans. |
| Depends on | `owns.1 - node-owns-globs-and-parallel-batches` |

## Prose

`CONTEXT.md:74` explicitly calls for *"spike nodes that never land"* and `CONTEXT.md:52` notes humans decide *"which of several valid options should we choose."* Today, a mid-quest human decision forces an agent to abuse `block` on a coding node (which trips Warden's `human_steer` plug and stalls the node's own cycle count), and a spike has to pretend to be a normal graded code node.

Edge cases:
- **Legacy ledgers without `node_kind`:** fold cleanly to `Code` (or `Direct` when `quest_type = "direct"`), preserving 100% backward compatibility.
- **Interaction with `dag-fsm-v2` git ancestry:** `Gate` nodes land with `commit = None`, so downstream `Code` nodes depending on a `Gate` walk/skip the commit-less gate cleanly without `E_MISSING_ANCESTOR`.
- **Warden interaction:** `Gate` nodes are intentional human touchpoints, NOT mid-build `human_steer` anomalies — verify `bp3 warden` does not falsely flag a `Gate` approval.
