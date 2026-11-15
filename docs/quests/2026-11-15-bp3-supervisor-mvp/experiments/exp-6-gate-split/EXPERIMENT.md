---
date: 2026-11-15
quest: ../QUEST.md
exp: 6
status: proposed
---

# Exp 6 — gate-split: only existence gates (skill change)

## TL;DR

Skill exp (rule 6.6). The induct-grade witness row
splits: `run_started` — a real Run did this work —
stays a gate. Settled/usage become scorecard
warnings: recorded, visible, never vetoing landed
work. Owner rules the exact matrix wording at
induct framing for this exp.

## Demo (design trace)

```text
matrix row was:  env preset ......... fail  -> BLOCKED
matrix row now:  run witnessed ...... pass
                 settle/usage ....... warn  (scorecard)
outcome: approved, warning carried into report
```

## Diagram

```text
witness evidence ──┬─ run_started present? ──no──► gate fails
                   └─ settled/usage? ──────no──► warning row only
```

## Pseudocode

```python
def witness_row(run):
    if not run.started: return FAIL("no real run")
    if not run.settled: return WARN("unsettled; usage partial")
    return PASS
```

| Field | Value |
|---|---|
| Intent | grade policy matches the platform test: bookkeeping never blocks the railway |
| Lane | standard |
| Output | induct-grade skill + workflow changes; skill tests |
| Depends on | Exp 2 (warnings surface), Exp 4 (run_started reliable) |

## Acceptance (fails today: settle absence blocks, matrix fail)

| Case | Expected |
|---|---|
| run_started only | approved path open; warning in matrix + report scorecard |
| no run_started | still blocked — anti-fake gate intact |
| settled with usage | clean pass, no warning |

## Acceptance test (goal block)

- **Objective:** unsettled-but-real work can land;
  fake work still cannot.
- **Prove by:** grade fixtures for the three cases
  through the updated workflow.
- **Done when:** fixtures show warn/pass/block
  exactly as tabled.

## Tests

known cases: Acceptance table as grade fixtures.
property-based: none (policy matrix; stated
omission). Demos: fixture matrices quoted in the
induct report.

## Context

Four blocks in the canceled pi quest trace to this
row, including one unsatisfiable-by-construction
case (a hooks exp cannot be live-settled by the
hook it is landing). The anti-fake half caught real
staged evidence once; it stays.
