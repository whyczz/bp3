---
date: 2026-11-16
goal: ../GOAL.md
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

## Amendment (owner-locked 2026-11-17): grade validations

Live again at mvp.3 (owner notified, then owner
directed the root fix and locked the name):
the audit child ran `git status --porcelain`,
the tree was clean, output was empty, and it
quoted that empty output verbatim (`quote: ""`).
`typedEvidence` requires a non-empty quote, so
the row degraded to `missing` and paged the
human a second time for grader paperwork.

Owner design, locked: **grade validations**.
Each validation is a plug (Phoenix-plug style):
deterministic code, ctx in, one typed evidence
row out, expectation declared in the validation
itself. Silence can be the expectation.

```text
grade workflow
  -> validations pipeline (deterministic, pre-audit)
       validate_git_clean            git status --porcelain, expect empty
       validate_clean_commit         git show + porcelain
       validate_run_folder_present   tape.log + notes.md exist
       validate_handoff_by_child     ledger handoff line
       validate_env_run_id_stamped   ledger run_id
     -> adherence rows minted by code, token for empty
        stdout is "(empty stdout, exit 0)", machine-minted
  -> audit child (LLM) builds ONLY acceptance rows
  -> normalize (unchanged anti-slop) -> review/check verdicts
```

```python
def validate_git_clean(ctx) -> Row:
    out = run("git status --porcelain", cwd=ctx.desk)
    ok = (out == "")                      # silence IS the pass condition
    return Row("adherence: no hand-edited state", rung=2,
               evidence={kind: "command",
                         ref: "git status --porcelain",
                         quote: "(empty stdout, exit 0)" if ok else out},
               verdict="pass" if ok else "fail")
```

Rules: adherence rows are never hand-quoted by
an LLM again. Acceptance rows remain the audit
child's; an untyped acceptance row is still an
audit-internal re-collect, then an explicit
audit failure — never an FSM verdict. A second
papercut in the same run joins scope: review
and check children cast verdicts in parallel;
the first negative moves state and the second
cast eats `E_ILLEGAL_EDGE`. That race must read
as a named, expected race in the outcome, not
an unexplained refusal. This node is pulled
forward ahead of mvp.4 at owner direction:
mvp.3's re-grade depends on the fixed grader.

## Acceptance

| Case | Expected |
|---|---|
| untyped row produced | the audit re-collects the named rows internally; the FSM sees no verdict until every row carries typed evidence (command/file/ledger + quote) |
| evidence still uncollectable | the grade returns an explicit audit failure naming the row and the collection error — distinguishable from a product `needs_fix` in outcome, reason, and ledger text |
| real defect still gates | a fixture with a genuinely failing case grades `needs_fix` (or blocks at cap) exactly as before |
| regression: config.1 shape | a replay of the config.1 cycle-1 scenario (green product, lazy audit) approves without paging the human |
| cycle accounting | an audit retry does not increment the exp cycle and writes no author-facing verdict |
| validations mint adherence rows | all adherence rows (git-clean, clean commit, run folder present, handoff by child, env run-id stamped) are produced by the deterministic validations pipeline before the audit child spawns; the audit brief no longer asks the LLM for adherence rows |
| regression: mvp.3 empty-stdout trap | a fixture reproducing the mvp.3 row (`git status --porcelain` clean, empty output) grades on merits with quote `"(empty stdout, exit 0)"`; no `missing` downgrade, no `blocked` page |
| verdict race named | when one verdict child moves state first, the other child's refused cast is reported as an expected verdict race in the outcome/refusals, never as an unexplained failure |

## Cycle 2 fix (owner A, 2026-11-17)

Cycle-1 grade on `5cce4cc`: the validations
pipeline worked for git-clean (pass, quote
`"(empty stdout, exit 0)"`), the verdict race
read as expected, and all acceptance rows
passed. One validation false-failed:
`adherence: run folder present` quoted
"no run folder with tape.log and notes.md"
while `runs/20261117T033939Z-handoff-.../`
on disk holds exactly `tape.log` + `notes.md`.
Named fix, verbatim for cycle 2: make
`validate_run_folder_present` trustworthy —
the observation transport must emit canonical
`<folder> tape=yes|no notes=yes|no` lines
(one shell one-liner, not free-form prose)
and/or the validation must parse the transport
variants tolerantly; add a regression test
feeding transport variants (canonical lines,
prose-shaped lines, empty list) and proving
the existing handoff folder passes. Do not
weaken the fail case: a folder missing
`tape.log` or `notes.md` still fails.

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
