---
node: research.1
---

# research.1 - research-and-explore-nodes

TL;DR
Wire the `Research` and `Explore` node lifecycles: `Research` enforces docs-only commits (`E_DOC_ONLY_NODE`) while allowing updates to downstream `todo` `NODE.md` / `QUEST.md` specs (and refusing edits to non-`todo` nodes); `Explore` adds `--target`, `--max-iterations`, `--budget-min`, `e iterate` (hard cap -> `E_EXPLORE_BOUND`), docs-only isolation under `docs/quests/<q>/explores/<node>/`, and `--outcome hit | missed | inconclusive`.

## Acceptance gates

Design trace:

```text
# 1. Research node: docs-only report + allowed to sharpen downstream `todo` NODE.md
$ bp3 q demo c r1 --kind research
$ bp3 q demo c c2 --depends-on r1
$ bp3 q demo n r1 e handoff --commit $C_TOUCHES_SRC --reason "oops"
-> exit 1, E_DOC_ONLY_NODE naming "src/quest/main.ml"
$ bp3 q demo n r1 e handoff --commit $C_TOUCHES_LANDED_NODE_MD --reason "rewrite history"
-> exit 1, E_PROTECTED_FILE naming "docs/quests/demo/nodes/d1/NODE.md"
$ bp3 q demo n r1 e handoff --commit $C_REPORT_AND_C2_NODE_MD --reason "grounded c2 spec"
-> exit 0, state: "landed", fin: "node_fin"

# 2. Explore node: target + iteration/time bound + isolated experiments + outcome
$ bp3 q demo c ex1 --kind explore --target "make check < 10s" --max-iterations 2 --budget-min 15
$ bp3 q demo n ex1 e iterate --note "run 1: 14.2s"
-> exit 0, {"ok": true, "explore": {"iterations": 1, "max_iterations": 2, ...}}
$ bp3 q demo n ex1 e iterate --note "run 2: 8.7s"
-> exit 0, {"ok": true, "explore": {"iterations": 2, "max_iterations": 2, ...}}
$ bp3 q demo n ex1 e iterate --note "run 3"
-> exit 1, E_EXPLORE_BOUND
$ bp3 q demo n ex1 e handoff --commit $C_TOUCHES_SRC --outcome hit --reason "leaked code"
-> exit 1, E_DOC_ONLY_NODE
$ bp3 q demo n ex1 e handoff --commit $C_EXPLORE_REPORT --outcome hit --reason "8.7s verified"
-> exit 0, state: "landed", fin: "node_fin", "explore": {"outcome": "hit", ...}
```

Runnable goal block:
- **objective:** Make `Research` (report + downstream `todo` spec refinement) and `Explore` (bounded experiment with target, iteration/time cap, isolated artifacts, and structured outcome) first-class, deterministically checked DAG nodes.
- **prove by:** Unit tests in `test/unit/test_store.ml` covering `Research` path allowlist (`docs/**` + downstream `todo` `NODE.md` vs non-`todo` `NODE.md` vs `src/`), `Explore` metadata folding (`target`, `max_iterations`, `iterations`, `budget_min`, `over_budget`, `outcome`), and `E_EXPLORE_BOUND` + fixture tests exercising both end-to-end + `make check-full`.
- **done when:** `make check-full` exits `0`, `Research` refuses `src/` and non-`todo` `NODE.md` edits while allowing downstream `todo` `NODE.md` updates, and `Explore` enforces `--target`, `max_iterations` on `e iterate`, docs-only isolation, and `--outcome` on `handoff`.

## Diagram

```text
Research:
  todo --handoff(docs/** only; own/non-todo NODE.md locked; downstream todo NODE.md allowed)--> landed

Explore:
  todo --iterate(iterations < max_iterations)--> todo (iterations+1, logged)
       --iterate(iterations >= max_iterations)--> E_EXPLORE_BOUND (stop & write report!)
       --handoff(docs/** only, --outcome hit|missed|inconclusive)--> landed
```

## Pseudocode

```python
def check_doc_only_node(quest, self_node, kind, node_states, changed_paths, allow_protected):
    non_docs = [p for p in changed_paths if not p.startswith("docs/")]
    if non_docs:
        raise E_DOC_ONLY_NODE(non_docs)
    for p in changed_paths:
        m = match_node_md(quest, p)  # docs/quests/<quest>/nodes/<other>/NODE.md
        if m is not None:
            if m == self_node and not allow_protected:
                raise E_PROTECTED_FILE([p])
            if node_states.get(m) != "todo" and not allow_protected:
                raise E_PROTECTED_FILE([p])
```

## Tables

| Field | Value |
|---|---|
| Intent | Turn web/codebase research (that refines downstream specs) and bounded hands-on experiments into disciplined, enforceable DAG nodes. |
| Lane | standard |
| Output | `Research` and `Explore` path/bound/outcome validation + `e iterate` edge in `src/quest/{store,main,render,names,cli}.ml`, unit + fixture tests. |
| Acceptance | Fails today: `--target`, `--max-iterations`, `--budget-min`, `--outcome`, and `e iterate` are rejected as `E_USAGE`; `Research`/`Explore` have no docs-only or bound checks. |
| Depends on | `kinds.1 - typed-node-kinds` |

## Prose

`Research` and `Explore` split the two kinds of pre-code discovery cleanly:
- **`Research`** reads external docs, web sources, and the repo, writes a sourced report (`docs/quests/<q>/research/<node>/REPORT.md` or `docs/dossiers/`), and updates downstream `todo` `NODE.md` / `QUEST.md` specs so downstream `Code` nodes start with grounded facts instead of hand-copied notes.
- **`Explore`** runs hands-on prototypes or benchmarks aimed at a concrete `--target` under a `--max-iterations` / `--budget-min` cap, keeps throwaway scripts + `REPORT.md` inside `docs/quests/<q>/explores/<node>/` (never leaking into `src/`), and closes with `hit | missed | inconclusive` — where `missed` and `inconclusive` still land cleanly so a downstream `Human_gate` can decide whether to pivot.

Edge cases:
- **Closing `Explore` past `budget_min`:** `handoff --outcome ...` is NEVER blocked by `budget_min` (only surfaced as `over_budget: true` in `bp3 q r`) so an agent that slightly overruns wall time can always commit its report instead of getting trapped.
- **`Explore` without `--target`:** refused at node creation with `E_USAGE` so every exploration states its direction up front.
- **`Explore` without `--outcome` on `handoff`:** refused with `E_USAGE` listing `hit | missed | inconclusive`.
- **Optional `e iterate`:** `Explore` nodes may close directly on `handoff --outcome ...` with 0 `iterate` calls if a single pass answered the question.
