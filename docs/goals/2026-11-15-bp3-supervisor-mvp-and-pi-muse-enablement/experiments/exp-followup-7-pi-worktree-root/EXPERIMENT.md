---
date: 2026-11-16
goal: ../GOAL.md
exp: followup.7
status: proposed
---

# followup.7 - pi-worktree-root: dispatcher resolves the worktree it was spawned in

## TL;DR

dogfood.4 papercut (owner gate ruling, 2026-11-16):
the dispatcher's `resolveRepoRoot` walks to the git
common dir's parent — the main checkout — even when
the extension was loaded inside a quest worktree.
Attempt 1 of the dogfood.4 drive refused
`E_BP3_FAILED` because the main checkout's older
`bin/bp3` has no `harness` door; the drive pinned
`BP3_PI_BP3_BIN` by hand. Fix: the dispatcher
resolves the *worktree* root (where its bp3 and its
desks live), while quest state still resolves via
the common dir inside bp3, where it belongs.

## Demo (design trace)

```text
before: pi -e bp3-pi (in quest worktree)
  resolveRepoRoot -> main checkout -> bin/bp3 (no harness door)
  record-init refused E_BP3_FAILED; drive pins BP3_PI_BP3_BIN by hand
after: resolveRepoRoot -> the worktree root
  bin/bp3 is the worktree's; record-init works; no pin needed
```

## Diagram

```text
cwd in worktree ─► git rev-parse --show-toplevel ─► worktree root
                        │ bp3 binary + child cwd
                        ▼
              bp3 harness (common-dir state inside bp3)
```

## Pseudocode

```python
def resolveRepoRoot(cwd):
    return git_toplevel(cwd)        # worktree-aware; falls back up-tree
    # never: dirname(git_common_dir(cwd)) as the working root
```

| Field | Value |
|---|---|
| Intent | extension works from any worktree with zero hand pins |
| Lane | standard |
| Output | dispatcher root fix + regression tests |
| Depends on | followup.5, followup.6, dogfood.4 |

## Acceptance

| Case | Expected |
|---|---|
| worktree root | extension loaded from a quest worktree resolves that worktree as root; `record-init` succeeds with no `BP3_PI_BP3_BIN` set |
| main checkout unchanged | from the main checkout, root resolves to the main checkout; followup.5/.6 drives still pass |
| nested subdir | from a nested subdir of a worktree, root resolves to that worktree's top (extends followup.5's repo-root case) |
| common-dir state intact | Run derivations still land in the shared `<git-common-dir>/bp3/run-lifecycle-derivations/`; no per-worktree proof split |
| regression suite | `extensions/bp3-pi/test/` covers worktree, main, and nested cases; full suite green |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** no hand-pinned bp3 binary, ever;
  the worktree the conductor sits in is the root
  the dispatcher serves.
- **Prove by:** a quest-worktree drive with
  `BP3_PI_BP3_BIN` unset: record-init + finished
  derivation, plus the suite.
- **Done when:** worktree drive derives `finished`
  with zero env pins beyond the ruling's, observed.

## Tests

Unit: root resolution across main checkout, linked
worktree, nested subdir, non-git dir (typed
refusal, fail-open intact). Drive: real-pi trivial
spawn from a quest worktree, no pin, `finished`.
The dogfood.4 attempt-1 refusal is the regression
case; it must be reproducible before the fix and
impossible after.

## Context

dogfood.2's rule "resolve repo root via git common
dir, never bare process.cwd()" was aimed at the
child-cwd bug in the canceled quest. In a worktree
world the common dir and the working root are
different answers to different questions: state is
shared (common dir), work is local (toplevel).
bp3 itself already knows this; the dispatcher
picked the wrong one for its binary and cwd.
