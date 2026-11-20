---
date: 2026-11-19
quest: ../../QUEST.md
node: verify.1
status: proposed
---

# verify.1 - red-first: a commit's tests must fail without it

## TL;DR

`scripts/red-first [<sha>]` runs the commit's tests against its
parent's code and expects red. A test that passes without the
change does not test the change. `refactor:` commits expect green.
No mutant files, nothing to maintain, no tokens.

## Acceptance gates

Observed today:

```text
$ ./scripts/red-first
zsh: no such file or directory: ./scripts/red-first
```

Design trace:

```text
$ ./scripts/red-first 92cb256          # fix: launch order + its test
red-first: red (run-suites)
$ ./scripts/red-first <vacuous>        # new test also passes on the parent
red-first: FAIL tests pass without the change: test/foo.sh
$ ./scripts/red-first d6a711f          # refactor: bash runner -> OCaml
red-first: green (refactor)
$ ./scripts/red-first 348db50          # test: backfill, no code change
red-first: n/a (test-only; the grader breaks the code)
```

```yaml
objective: a commit's changed tests are seen to fail on the parent's code
prove by:
  - test/red-first.sh (fixture tier) over a planted repo with one
    commit per case below; each prints its exact line and exit code
  - ./scripts/red-first on this repo's HEAD, timed
done when:
  - every case row prints its line and exits as the table says
  - a planted vacuous test (passes on the parent) exits 1
  - the temp worktree is gone after every case, including a failed one
  - red-first on this repo runs in under 30s
```

## Diagram

```text
<sha> ──► changed files ──► tests (test/**, extensions/*/test/**)
                        └─► code  (everything else, docs/** excluded)
            │
            ▼ tests and code both changed
  worktree at <sha>^  +  <sha>'s copies of the changed tests
            │
            ▼
  ./scripts/check-changed.sh <changed tests>   (the parent's selector)
            │
   rc≠0 ─► red (<first failing step>)     refactor: rc≠0 ─► FAIL
   rc=0 ─► FAIL tests pass without it     refactor: rc=0 ─► green
```

## Pseudocode

```python
def red_first(sha="HEAD"):
    kind = conventional_type(subject(sha))        # feat, fix, refactor, test, ...
    tests, code = split(changed(sha))             # docs/** counts as neither
    if not tests and not code: return na("no code or test change")
    if not tests:
        if kind in ("feat", "fix"): return fail("feat/fix with no test change")
        return na(f"{kind}, no test change")
    if not code: return na("test-only; the grader breaks the code")
    with worktree(parent(sha)) as wt:             # removed on every exit
        overlay(wt, sha, tests)                   # deleted tests are removed
        rc, step = run(wt, "./scripts/check-changed.sh", *tests)
    if kind == "refactor":
        return green("refactor") if rc == 0 else fail(f"refactor changed behavior: {step}")
    return red(step) if rc != 0 else fail(f"tests pass without the change: {tests}")
```

## Tables

| Field | Value |
|---|---|
| Intent | the "seen it fail" check, done by a script instead of a grader round |
| Lane | standard |
| Output | `scripts/red-first`, `test/red-first.sh`, one `fixture` row in `test/suites.tsv` |
| Acceptance | the case table below, on a planted repo; fails today (no script) |
| Depends on | none |

| Case | Line | Exit |
|---|---|---|
| fix + test, test fails on parent | `red-first: red (<step>)` | 0 |
| feat/fix + test, test passes on parent | `red-first: FAIL tests pass without the change: <files>` | 1 |
| refactor, tests green on parent | `red-first: green (refactor)` | 0 |
| refactor, tests red on parent | `red-first: FAIL refactor changed behavior: <step>` | 1 |
| feat/fix, no test change | `red-first: FAIL feat/fix with no test change` | 1 |
| test-only commit | `red-first: n/a (test-only; the grader breaks the code)` | 0 |
| docs/chore, no test change | `red-first: n/a (<type>, no test change)` | 0 |
| dirty tree or unknown sha | `red-first: <reason>` | 2 |

## Prose

The test-pyramid graders spent rounds on tests that could not fail:
a probe whose copied `sleep` was killed by code signing, a "bound met"
claim never seen red. The owner rejected hand-written mutant patches
as token waste that rots ("this is a waste of tokens no? we're
building deterministic systems?"). The parent commit is the mutant:
it is the code without the change, for free.

Edge cases:

- **OCaml tests that call a new function** fail to build on the
  parent. That counts as red, labeled by the failing step (the build),
  so the grader sees it is weak.
- **Test-only commits** (backfills) have no parent to fail against.
  red-first says n/a and the grader's extra check carries the teeth:
  break one line of the code the new tests claim to cover, in its own
  desk, and see red (grade.1).
- **The selector is the parent's.** red-first runs the parent's
  `scripts/check-changed.sh` with the changed test paths, so a test no
  suite row claims selects only the unit tier and shows green: the
  FAIL line names the file, which is the right outcome (an orphan test
  is not run by any gate).
- The worktree lives under `$TMPDIR` and is removed by an EXIT trap.
