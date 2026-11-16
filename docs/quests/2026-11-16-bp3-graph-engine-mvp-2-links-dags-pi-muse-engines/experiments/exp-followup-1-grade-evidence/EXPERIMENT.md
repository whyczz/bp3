---
date: 2026-11-16
quest: ../QUEST.md
exp: followup.1
status: proposed
---

# followup.1 - grade-evidence: missing evidence is not a defect

## TL;DR

Papercut found live (config.1, cycle 1, owner
notified): the grade workflow's audit child can
return matrix rows with no typed evidence
("row carried no typed evidence"). A row without
evidence cannot pass, so the verdict degrades to
fix-first — and at `max_cycles: 1` that escalates
straight to `blocked` and pages the human, for a
grader paperwork failure on a green product.

Fix the evidence contract in the grade workflow:
every matrix row must carry typed evidence
(command/file/ledger) or the audit re-runs its
own collection. Evidence-missing is a grader
internal retry; it never reaches the FSM as a
verdict, never burns an author cycle, and never
pages the human. Defects and evidence gaps take
different roads.

## Demo (design trace)

```text
before: audit row {case: "local only", evidence: none}
  -> verdict missing -> fix-first at cap -> blocked -> human paged
  (config tests were green the whole time)

after:  audit row without typed evidence
  -> audit re-collects (one internal retry, named rows)
  -> row carries typed evidence -> judged pass/fail on merits
  -> human paged only for actual decisions
```

## Diagram

```text
audit child -> rows -> each row typed evidence?
                          | no              | yes
                          v                 v
                    re-collect (audit)   judge on merits
                    (never an FSM        (ship / needs_fix /
                     verdict)             blocked only at cap)
```

## Pseudocode

```python
def audit(exp, commit):
    rows = collect_rows(exp, commit)
    for row in rows:
        if not typed(row.evidence):            # command|file|ledger + quote
            rows = recollect(rows, missing=[row.case])   # audit-internal
    assert all(typed(r.evidence) for r in rows)  # or explicit audit failure
    return judge(rows)                           # verdicts only from evidence
```

| Field | Value |
|---|---|
| Intent | a human is paged for decisions, never for grader paperwork |
| Lane | standard |
| Output | grade workflow evidence contract + regression tests; audit retry semantics named in the traverse skill surface |
| Depends on | mig.2 (traverse workflows), config.1 (the live papercut) |

## Acceptance

| Case | Expected |
|---|---|
| untyped row produced | the audit re-collects the named rows internally; the FSM sees no verdict until every row carries typed evidence (command/file/ledger + quote) |
| evidence still uncollectable | the grade returns an explicit audit failure naming the row and the collection error — distinguishable from a product `needs_fix` in outcome, reason, and ledger text |
| real defect still gates | a fixture with a genuinely failing case grades `needs_fix` (or blocks at cap) exactly as before |
| regression: config.1 shape | a replay of the config.1 cycle-1 scenario (green product, lazy audit) approves without paging the human |
| cycle accounting | an audit retry does not increment the exp cycle and writes no author-facing verdict |

## Acceptance test (goal block)

- **Objective:** missing evidence is a grader
  retry, never a human page.
- **Prove by:** grade fixtures — (a) audit stub
  returning one untyped row, (b) genuinely
  failing case — driven through the public grade
  workflow; observe outcomes and cycle counts.
- **Done when:** (a) approves or retries without
  touching the FSM cycle, (b) still gates,
  observed.

## Tests

Known cases: untyped-row recollection, explicit
audit failure shape, real-defect parity, cycle
count unchanged across audit retries.

Property-based: for any matrix, no verdict is
emitted while a row lacks typed evidence
(generator over row/evidence shapes).

## Context

Found live at config.1's first grade: the product
was green (`test/config.sh` ok), the audit simply
didn't attach receipts, and `max_cycles: 1` turned
paperwork into an owner page. Owner ruled during
the run: notify papercuts and add followups to
fix them. This is that followup.
