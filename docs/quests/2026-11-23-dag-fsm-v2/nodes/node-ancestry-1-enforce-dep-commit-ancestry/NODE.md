---
node: ancestry.1
---

# ancestry.1 - enforce-dep-commit-ancestry

TL;DR
Verify `Gitx.is_ancestor dep.commit commit` on `handoff` for every landed dependency carrying a commit, refusing diverged or stale commits with `E_MISSING_ANCESTOR`.

## Acceptance gates

Design trace:

```text
# n1 landed at commit $C1; n2 depends on n1
# Commit $C_STALE branched before $C1 (not a descendant of $C1):
$ bp3 q demo n n2 e handoff --commit $C_STALE --reason "try"
-> exit 1:
   {"ok": false, "error": {"code": "E_MISSING_ANCESTOR",
    "facts": {"commit": "$C_STALE", "missing": [{"node": "n1", "commit": "$C1"}]},
    "guidance": "Rebase or merge landed dependency commits before handoff."}}

# Commit $C2 descends from $C1:
$ bp3 q demo n n2 e handoff --commit $C2 --reason "rebased onto n1"
-> exit 0: {"ok": true, "state": "handed_off", ...}

# Deleted dep or landed dep with commit=None: skipped (no false refusal)
```

Runnable goal block:
- **objective:** Prevent a node from handing off a commit that does not contain its landed dependencies' code commits.
- **prove by:** Pure unit tests for ancestry check helper + git-repo fixture test covering diverged branch (`E_MISSING_ANCESTOR`), rebased/merged branch (passes), `deleted` dep (skipped), and commit-less dep (skipped) + `make check-full`.
- **done when:** `make check-full` exits `0` and diverged `handoff` fails deterministically with `E_MISSING_ANCESTOR` naming every missing `(node, commit)`.

## Diagram

```text
handoff(node, commit)
  |
  +--> clean tree? (E_DIRTY_TREE)
  +--> all quest & node deps landed/deleted? (E_DEPENDENCY)
  +--> for each dep in node_deps where dep.state == "landed" and dep.commit != None:
  |      is_ancestor(dep.commit, commit)?
  |        no  --> refuse E_MISSING_ANCESTOR(missing=[...])
  |        yes --> continue
  +--> bind commit, advance state
```

## Pseudocode

```python
def missing_ancestors(deps, commit, fold_node, is_ancestor):
    missing = []
    for d in deps:
        st = fold_node(d)
        if st.state == "landed" and st.commit is not None:
            if not is_ancestor(st.commit, commit):
                missing.append({"node": d, "commit": st.commit})
    return missing
```

## Tables

| Field | Value |
|---|---|
| Intent | Close the gap between DAG dependency edges and actual git commit history on `handoff`. |
| Lane | standard |
| Output | Pure ancestry check + `E_MISSING_ANCESTOR` constant in `src/quest/names.ml`, wired into `Main.do_update` (`handoff` branch), plus unit + fixture tests. |
| Acceptance | Fails today: `src/quest/main.ml:235-243` checks only `ds.st = "landed"`, so a diverged commit without `dep.commit` hands off with exit `0`. |
| Depends on | `fsm.1 - collapse-verify-and-auto-land` |

## Prose

When parallel writers (like `/swarm` worktrees) or separate sessions work on a quest DAG, `depends_on` means Node B builds on Node A's landed code. Checking only `A.state == "landed"` allows a stale worktree to hand off a commit that never merged or rebased Node A — wasting a full grade cycle or silently dropping Node A's changes.

Edge cases:
- **Deleted dependency (`ds.st = "deleted"`):** skipped; deleted nodes are satisfied without code ancestry.
- **Commit-less landed dependency (`ds.last_commit = None`):** skipped; preserves forward compatibility with `Human_gate` nodes in `2026-11-23-dag-contracts`.
- **Transitive deps:** checking direct landed deps suffices when every upstream node was itself checked on `handoff` (git ancestry is transitive). If a direct dep was deleted/commit-less, walk past it only if needed — keep v1 direct and note transitive walk if `Human_gate` nodes later sit between two `Code` nodes.
- **Quest-level `--depends-on`:** left as state-only (`dep_satisfied`), since cross-quest deps live on different branches until promoted to `master`.
