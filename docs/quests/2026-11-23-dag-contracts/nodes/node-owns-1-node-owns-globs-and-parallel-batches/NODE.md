---
node: owns.1
---

# owns.1 - node-owns-globs-and-parallel-batches

TL;DR
Add pure OCaml `src/quest/owns.ml` (glob matching + sound disjointness + `parallel_batches`), `--owns <g1,g2>` on node creation/update, `parallel_batches` on `bp3 q r <quest>`, and deterministic `E_SCOPE_VIOLATION` / `E_PROTECTED_FILE` enforcement on `handoff`.

## Acceptance gates

Design trace:

```text
$ bp3 q demo c a --owns "src/a/**"
$ bp3 q demo c b --owns "src/b/**"
$ bp3 q demo c c --owns "src/a/x.ml"
$ bp3 q r demo | jq -c '{ready, parallel_batches}'
-> {"ready":["a","b","c"],"parallel_batches":[["a","b"],["c"]]}

# Protected file edit without declaring it in --owns:
$ bp3 q demo n a e handoff --commit $C_TOUCHES_GRADING --reason "sneaky"
-> exit 1, E_PROTECTED_FILE naming "GRADING.md"

# Out-of-scope file edit:
$ bp3 q demo n a e handoff --commit $C_TOUCHES_B --reason "oops"
-> exit 1, E_SCOPE_VIOLATION naming "src/b/y.ml"

# In-scope edit (+ docs/quests/demo/LOG.md always allowed):
$ bp3 q demo n a e handoff --commit $C_TOUCHES_A --reason "clean"
-> exit 0, state: "handed_off"
```

Runnable goal block:
- **objective:** Make parallel-safety (`/swarm`) and file/governance scope locks deterministic in OCaml.
- **prove by:** OUnit + QCheck2 soundness tests in `test/unit/test_owns.ml` (`matches p a && matches p b => not (disjoint a b)`), fixture test covering `parallel_batches`, `E_PROTECTED_FILE`, `E_SCOPE_VIOLATION`, and `LOG.md` carve-out + `make check-full`.
- **done when:** `make check-full` exits `0` and all unit/property/fixture assertions pass.

## Diagram

```text
create/owns(--owns globs) --> node ledger
                                  |
       +--------------------------+--------------------------+
       v                                                     v
bp3 q r <quest>                                       handoff(commit)
  ready nodes + owns                                    diff-tree changed paths
  --> sound disjointness                                --> protected_files check (E_PROTECTED_FILE)
  --> parallel_batches: [[...], [...]]                  --> owns check (E_SCOPE_VIOLATION)
```

## Pseudocode

```python
PROTECTED = ["GRADING.md", "CONSTRAINTS.md", "scripts/receipt", "scripts/red-first"]

def check_handoff_scope(quest, node, owns, changed_paths):
    protected = PROTECTED + [f"docs/quests/{quest}/nodes/{node}/NODE.md"]
    bad_protected = [p for p in changed_paths if p in protected and not matches_any(p, owns)]
    if bad_protected:
        raise E_PROTECTED_FILE(bad_protected)
    if owns:
        allowed_extra = {f"docs/quests/{quest}/LOG.md"}
        bad_scope = [p for p in changed_paths if p not in allowed_extra and not matches_any(p, owns)]
        if bad_scope:
            raise E_SCOPE_VIOLATION(bad_scope)

def parallel_batches(ready_nodes):
    batches = []
    for n in sorted(ready_nodes):
        placed = False
        if n.owns:  # empty owns = wildcard, never auto-parallelized
            for b in batches:
                if all(m.owns and globs_disjoint(n.owns, m.owns) for m in b):
                    b.append(n); placed = True; break
        if not placed:
            batches.append([n])
    return batches
```

## Tables

| Field | Value |
|---|---|
| Intent | Enforce file boundaries and compute parallel-safe ready batches deterministically inside `bp3 q`. |
| Lane | standard |
| Output | `src/quest/owns.ml`, updated `src/quest/{cli,store,render,main,names}.ml`, `test/unit/test_owns.ml`, and fixture test. |
| Acceptance | Fails today: `--owns` is rejected as `E_USAGE`, `bp3 q r` has no `parallel_batches`, and `handoff` accepts commits editing `GRADING.md` or another node's files. |
| Depends on | `2026-11-23-dag-fsm-v2` |

## Prose

Soundness over cleverness: `Owns.disjoint` compares normalized segment prefixes (`a/b/**` vs `a/c/**` -> disjoint; `a/**` vs `a/b.ml` -> overlapping; any leading `*`/`**` or empty `owns` -> overlapping). A QCheck2 property test generates random path trees and glob pairs to prove that no path can ever match two globs declared disjoint.

Edge cases:
- **Empty `owns` (legacy or unconstrained nodes):** never fails `E_SCOPE_VIOLATION`, still enforces `E_PROTECTED_FILE` (must explicitly declare a protected file in `owns` to edit it), and always sits in its own singleton batch in `parallel_batches`.
- **Renames/deletions in `git diff-tree`:** check *both* old and new paths on rename (`R`) so moving a protected file cannot bypass `E_PROTECTED_FILE`.
- **Mid-flight scope update:** `bp3 q <q> owns <n> --owns <...> --reason <why>` logs an append-only `owns` ledger line (same mutable-but-logged pattern as `bp3 q <q> dep`).
