---
date: 2026-11-14
goal: ../GOAL.md
exp: 1
status: proposed
---

# Exp 1 — Worktree util layer

## TL;DR

The low-level mechanics only: derive a worktree path
from `(quest, exp, run-id)`, create a worktree on a
branch or detached at a commit, inspect its ref and
dirty state, and remove it — with the dirty refusal
inside the remove primitive itself. No registry, no
override, no staleness policy, no workflow behavior.

## Demo (design trace)

```text
derive("demo","exp-a","R1") -> .bp3/worktrees/demo/exp-a/R1
create(path, branch="bp3/exp/demo/exp-a") -> worktree on branch
create(path2, commit="a09109c3") -> detached worktree (repeatable)
inspect(path) -> {ref, dirty:false}
remove(path) after an edit -> REFUSED (dirty), worktree untouched
```

## Diagram

```text
(quest, exp, run-id) ──derive──► path
path + branch|commit ──git worktree add──► worktree
worktree ──inspect──► {ref, dirty, changed_count}
worktree ──remove──► inspect dirty? refuse : git worktree remove
```

## Pseudocode

```python
def derive(quest, exp, run_id):        # pure; hard-coded layout
    return f".bp3/worktrees/{quest}/{exp}/{run_id}"

def remove(path, force=False):
    if inspect(path).dirty and not force:
        refuse("E_DIRTY_TREE")          # safety lives HERE, lowest layer
    git_worktree_remove(path)
```

| Field | Value |
|---|---|
| Intent | git mechanics any caller can trust blindly |
| Lane | standard |
| Output | util functions in the OCaml binary's worktree mode; fixture suite in a scratch repo |
| Depends on | none |

## Acceptance (fails today: no worktree code exists)

| Case | Expected |
|---|---|
| derive | exact hard-coded path; generated slugs never escape `.bp3/worktrees/` |
| create on branch | worktree exists, branch checked out |
| create `--commit` twice | two detached worktrees at the same sha |
| create on an already-checked-out branch | clean refusal, no raw git error leaked |
| remove after an edit | `E_DIRTY_TREE`; worktree and edit intact |
| remove with `--force` | worktree removed; the force is explicit in the call |

## Acceptance test (goal block)

- **Objective:** trustworthy worktree primitives.
- **Prove by:** `test/worktree.sh` util cases in a
  scratch repo; dirty-removal case asserted impossible
  without `--force`.
- **Done when:** all cases pass; safety proven at the
  primitive, not at a caller.

## Tests

known cases: the Acceptance table · property-based:
path derivation is pure and total over generated
(quest, exp, run) slugs and never escapes the root; a
dirty worktree is never removed without `--force` for
any generated edit set · fixtures: scratch-repo suite ·
demos: Demo trace, observed at landing.

## Context

Layer 1 of the settled split (owner, red-ink Round 3):
mechanics below, bookkeeping above, conventions on top.
The dirty refusal sits in the primitive because the
codebase's invariant rule is "safety at the lowest
writer" (Round 5) — a future caller cannot forget a
check that lives underneath it.
