---
date: 2026-11-19
quest: ../../QUEST.md
node: verify.2
status: proposed
---

# verify.2 - receipt: the handoff evidence is printed, not written

## TL;DR

`scripts/receipt` runs the gate and red-first on a clean HEAD and
prints a few lines of evidence: sha, exit codes, suite counts, wall
time. That text is the handoff `--reason`. Nobody types "robust";
claims come only from command output.

## Acceptance gates

Observed today:

```text
$ ./scripts/receipt
zsh: no such file or directory: ./scripts/receipt
```

Design trace:

```text
$ ./scripts/receipt
receipt 01d30b767fc5 fix(test): check-gates pins the gate plans exactly
check-full rc=0 run-suites: ok 26/26 wall 36.0s
red-first red (check-tiers)
$ echo $?
0
$ echo x >> readme.md && ./scripts/receipt
receipt: dirty tree; commit first
$ echo $?
2
```

```yaml
objective: one command prints the evidence a handoff carries
prove by:
  - test/receipt.sh (fixture tier) with --check and --red-first stubs
    for: both green; gate red; red-first FAIL; red-first n/a; dirty tree
  - ./scripts/receipt on this repo's HEAD
done when:
  - each case prints the lines and exit code in the table below
  - the printed check-full line is the gate's own summary line, copied
  - on this repo it exits 0 and prints exactly three lines
```

## Diagram

```text
clean HEAD ──► make check-full ──► rc + last "run-suites:" line + wall
          └──► scripts/red-first ──► its one line
                         │
                         ▼
     receipt <sha12> <subject>
     check-full rc=<n> <summary>
     red-first <line>
     exit 0 iff rc=0 and red-first did not FAIL
```

## Pseudocode

```python
def receipt(check="make check-full", red_first="./scripts/red-first"):
    if dirty(): die(2, "receipt: dirty tree; commit first")
    sha = head()
    rc, out, wall = run(check)
    summary = last_line_starting(out, "run-suites:") or f"wall {wall:.1f}s"
    rf_rc, rf_line = run(red_first, sha)
    print(f"receipt {sha[:12]} {subject(sha)}")
    print(f"check-full rc={rc} {summary}")
    print("red-first " + rf_line.removeprefix("red-first: "))
    return 0 if rc == 0 and rf_rc == 0 else 1
```

## Tables

| Field | Value |
|---|---|
| Intent | handoff evidence that cannot overclaim |
| Lane | micro |
| Output | `scripts/receipt`, `test/receipt.sh`, one `fixture` row |
| Acceptance | the case table, with stubbed commands; fails today (no script) |
| Depends on | verify.1 - red-first |

| Case | Last line | Exit |
|---|---|---|
| gate green, red-first red | `red-first red (<step>)` | 0 |
| gate green, red-first n/a | `red-first n/a (<why>)` | 0 |
| gate red | `check-full rc=<n> ...` then the red-first line | 1 |
| red-first FAIL | `red-first FAIL ...` | 1 |
| dirty tree | `receipt: dirty tree; commit first` | 2 |

## Prose

About half the test-pyramid grader findings were commit messages that
claimed more than was verified. The fix is not a better-worded rule
for the author; it is evidence the author cannot word at all. The
receipt is three lines of machine output. The author may append one
`unverified: ...` line by hand, naming a gap ("macOS only"); that is
the only free text, and it can only narrow what is claimed.

`--check` and `--red-first` exist so the fixture test can stub both;
running the real `make check-full` inside a suite that `make
check-full` runs would recurse.

The receipt needs a clean tree, so it runs after the commit and a
commit message can never quote its own receipt. The ledger carries
it (the handoff reason); the commit's Verification lists only the
commands run before committing and their exit codes. That is a skill
rule (grade.1), not a check here.
