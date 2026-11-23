---
date: 2026-11-23
quest: ../../QUEST.md
node: verify.2
status: proposed
---

# verify.2 - receipt: 4-line deterministic handoff evidence

## TL;DR

`scripts/receipt [<sha>]` runs `make check-full` and `scripts/red-first <sha>` on a clean commit and prints 4 deterministic lines — commit header, gate exit code + summary, `red-first` verdict, and test-file/line delta (`+added/-removed` under `test/`). Authors pass this receipt as the handoff `--reason`, and graders verify against it instead of hunting blind.

## Acceptance gates

Observed today:

```text
$ ls scripts/receipt
ls: scripts/receipt: No such file or directory
```

Design trace:

```text
$ ./scripts/receipt HEAD
receipt abc1234 feat(test): add red-first
check-full: rc=0 run-suites: ok 29/29 wall 38.2s
red-first: red (red-first)
tests: 1 file(s) changed (+42/-0 lines under test/)
# exit 0

# Dirty working tree -> exit 2, message on stderr
# check-full fails or red-first returns FAIL -> prints all 4 lines, exit 1
```

```yaml
objective: print deterministic handoff evidence (gate + red-first + test-delta) for any clean commit
prove by:
  - test/receipt.sh: clean passing commit -> 4 lines & rc 0; dirty tree -> rc 2; failing red-first -> rc 1 with FAIL line; deleted test lines -> negative count shown on tests: line; -h/--help -> stdout rc 0
  - make check-full
done when: test/receipt.sh passes (registered in test/suites.tsv) and ./scripts/receipt HEAD exits 0 on this node's own commit
```

## Diagram

```text
scripts/receipt [sha=HEAD]
   │
   ├─ check clean tree (git status --porcelain empty) -> dirty? exit 2
   ├─ resolve full sha & subject
   ├─ run gate (default: make check-full; overrideable via BP3_RECEIPT_GATE for unit fixtures)
   ├─ run scripts/red-first <sha>
   ├─ compute test diff stat (git diff --numstat <sha>^ <sha> -- test/)
   └─ print 4 lines; exit 0 iff gate_rc == 0 and red_first_rc == 0 else exit 1
```

## Pseudocode

```python
def receipt(sha="HEAD"):
    if git_status_porcelain() != "":
        die("dirty worktree; commit or clean first", rc=2)
    full, sha7, subject = git_commit_info(sha)
    gate_rc, gate_last = run_gate(env.get("BP3_RECEIPT_GATE", "make check-full"))
    rf_rc, rf_line = run_capture(["./scripts/red-first", full])
    files, added, removed = git_test_numstat(f"{full}^", full)
    print(f"receipt {sha7} {subject}")
    print(f"check-full: rc={gate_rc} {gate_last}")
    print(rf_line)
    print(f"tests: {files} file(s) changed (+{added}/-{removed} lines under test/)")
    return 0 if (gate_rc == 0 and rf_rc == 0) else 1
```

## Tables

| Field | Value |
|---|---|
| Intent | give authors and graders one machine-printed receipt carrying gate proof, red-first proof, and anti-test-weakening delta |
| Lane | micro |
| Output | `scripts/receipt` (new, executable bash), `test/receipt.sh` (new), `test/suites.tsv` (1 fixture row) |
| Acceptance | fails today (script does not exist); passes when `test/receipt.sh` and `make check-full` pass |
| Depends on | `verify.1 - red-first` |
| Must not touch | `src/quest/*`, `bin/bp3`, `skills/*`, `CONSTRAINTS.md` |

## Prose

Two lessons from `CONTEXT.md` combine here: deterministic proofs beat LLM prose (`CONTEXT.md:96`), and agents sometimes weaken or delete tests to pass (`CONTEXT.md:102`). Including `tests: N file(s) changed (+A/-D lines under test/)` makes test deletions immediately visible in 1 line so the grader knows instantly whether to audit deleted assertions.

Edge cases:
- **Root commit (no parent):** handle `git rev-parse --verify <sha>^` failure cleanly (`tests: initial commit`).
- **Allow `BP3_RECEIPT_GATE` override only in tests** (never in `GRADING.md` / real handoffs) so `test/receipt.sh` runs fast without recursively spawning `make check-full`.
- **Single-line summary:** capture the last non-empty line of the gate's stdout/stderr so line 2 stays compact and parseable.
