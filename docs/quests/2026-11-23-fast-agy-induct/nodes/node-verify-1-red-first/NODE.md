---
date: 2026-11-23
quest: ../../QUEST.md
node: verify.1
status: proposed
---

# verify.1 - red-first: deterministic BASE_FAIL_HEAD_PASS proof in <30s

## TL;DR

`scripts/red-first [<sha>]` proves that a commit's changed tests fail against its parent's implementation (`BASE_FAIL_HEAD_PASS`) in a detached temporary worktree, without an LLM hand-planting mutants. For `refactor:` commits it expects green; for docs/skill-only commits with no changed test files it prints `n/a` and exits 0.

## Acceptance gates

Observed today:

```text
$ ls scripts/red-first
ls: scripts/red-first: No such file or directory
```

Design trace (scratch fixture repo):

```text
$ ./scripts/red-first <feat-commit-with-real-test>
red-first: red (unit:test_foo)          # exit 0
$ ./scripts/red-first <feat-commit-with-vacuous-test>
red-first: FAIL (changed tests passed on parent <parent7>)   # exit 1
$ ./scripts/red-first <refactor-commit>
red-first: green (refactor)             # exit 0
$ ./scripts/red-first <docs-only-commit>
red-first: n/a (no test files changed)  # exit 0
$ ./scripts/red-first --bad-flag
usage: ...                              # exit 2
```

```yaml
objective: prove changed tests fail on parent code deterministically in <30s before handoff
prove by:
  - test/red-first.sh: fixture repo testing real feat test (red -> rc 0), vacuous test (green on parent -> rc 1), refactor commit (green -> rc 0), docs-only commit (n/a -> rc 0), missing/bad sha (rc 2), cleanup of temp worktree on trap
  - timed run on a real bp3 OCaml/test commit showing wall time < 30s
  - make check-full
done when: test/red-first.sh passes (registered in test/suites.tsv) and red-first catches a planted vacuous test with exit 1
```

## Diagram

```text
scripts/red-first [sha=HEAD]
   │
   ├─ inspect commit subject (refactor:?) and changed files (git diff --name-only sha^ sha)
   ├─ filter changed test files (test/*, *_test.ml, test_*.ml)
   │    └─ none? -> print "red-first: n/a (no test files changed)", exit 0
   ├─ mktemp -d worktree at sha^ (trap cleanup)
   ├─ overlay ONLY changed test files from sha onto sha^ worktree
   ├─ select targeted suites via scripts/check-changed.sh --list + dune test (if test/unit/*)
   ├─ run targeted suites in temp worktree:
   │    ├─ refactor:  green -> "red-first: green (refactor)" rc 0 | red -> "red-first: FAIL (refactor broke parent tests)" rc 1
   │    └─ otherwise: red   -> "red-first: red (<suite>)" rc 0    | green -> "red-first: FAIL (changed tests passed on parent)" rc 1
   └─ remove temp worktree cleanly
```

## Pseudocode

```python
def red_first(sha="HEAD"):
    full = git_rev_parse(sha)
    parent = git_rev_parse(f"{full}^")
    subject = git_show_subject(full)
    changed = git_diff_names(parent, full)
    test_files = [p for p in changed if is_test_path(p)]
    if not test_files:
        print("red-first: n/a (no test files changed)")
        return 0
    with temp_detached_worktree(parent) as wt:
        checkout_files(wt, full, test_files)      # handle deleted test files cleanly
        rc, first_fail = run_targeted_tests(wt, test_files)
    is_refactor = subject.startswith("refactor:") or subject.startswith("refactor(")
    if is_refactor:
        if rc == 0: print("red-first: green (refactor)"); return 0
        print(f"red-first: FAIL (refactor tests failed on parent: {first_fail})"); return 1
    else:
        if rc != 0: print(f"red-first: red ({first_fail})"); return 0
        print(f"red-first: FAIL (changed tests passed on parent {parent[:7]})"); return 1
```

## Tables

| Field | Value |
|---|---|
| Intent | replace manual LLM mutant-planting with a deterministic <30s `BASE_FAIL_HEAD_PASS` check |
| Lane | standard |
| Output | `scripts/red-first` (new, executable bash), `test/red-first.sh` (new), `test/suites.tsv` (1 fixture row) |
| Acceptance | fails today (script does not exist); passes when `test/red-first.sh` and `make check-full` pass |
| Depends on | none |
| Must not touch | `src/quest/*`, `bin/bp3`, `skills/*`, `CONSTRAINTS.md` |

## Prose

On `2026-11-22`, 4 of 11 `needs_fix` rounds were tests that could not fail, and every single grade spent minutes hand-planting mutants in `mktemp -d`. Overlaying a commit's test files onto its parent commit tests the exact implementation delta in seconds (dune cache builds a fresh worktree of `bp3` in ~1-2s).

Edge cases:
- **Compile failure on parent** (e.g. a new unit test references a brand-new OCaml function that didn't exist in `sha^`): counts as **red** (`rc != 0`), which is valid `BASE_FAIL_HEAD_PASS` for new APIs.
- **Deleted test files:** `git checkout <sha> -- <path>` fails on deleted files; skip deleted paths (and let `scripts/receipt`'s test-delta line surface deletions to the grader).
- **Worktree hygiene:** register `trap` to run `git worktree remove --force "$wt"` and `rm -rf "$wt"` so interruptions never leak `.git/worktrees` entries. Use `--root=.` for `dune test` inside the temp worktree.
- **CLI docstring rule:** supports `-h`/`--help` (stdout, rc 0, no state read).
