---
date: 2026-11-15
goal: ../GOAL.md
exp: mvp.7
status: proposed
---

# mvp.7 - grader-evidence-ladder: how a grade is earned

## TL;DR

Wire the five-rung evidence ladder into the grader:
quest/exp records, committed code + diff, demos and
tests run, style, then tape last — pointers
first, whole tape only on escalation. Grader skill
and `induct-grade` workflow change here, nowhere
else.

## Demo (design trace)

```text
grade run R (lying fixture):
  rung 1-2: exp claims X; diff is clean
  rung 3:   tests pass
  rung 5:   find-tape --run-id R --entry E
            -> entry contradicts the claim
  verdict:  block, citing rung 5 pointer E
```

## Diagram

```text
quest/exp ─► code+diff ─► demos/tests run ─► style ─► pointers ─► (whole tape)
   1            2               3               4          5        escalation
each rung only when the ones above leave the verdict undecided
```

## Pseudocode

```python
def grade(quest, exp, commit, run_id):
    for rung in [records, diff, run_demos_tests, style]:
        v = judge(rung)
        if decided(v): return v
    for ptr in derivation_pointers(run_id):        # rung 5a
        v = judge(resolve(ptr))                    # --entry, digest-verified
        if decided(v): return v
    return judge(whole_log(run_id))                # rung 5b: blocked/confused/lying only
```

| Field | Value |
|---|---|
| Intent | make the evidence ladder mechanical: pointers via bp3, not grader memory |
| Lane | standard |
| Output | updated grader instructions + `induct-grade` workflow consuming the ladder and `find-tape --entry` |
| Depends on | mvp.2 (pointer resolver), mvp.4 (supervisor as mechanism) |

## Acceptance (fails today: grader reads what it likes, whole tapes included)

| Case | Expected |
|---|---|
| lying fixture: clean diff/tests, pointer contradicts claim | block verdict citing the rung-5 pointer |
| clean fixture | verdict reached with zero whole-log reads |
| confused grade (rungs 1-4 undecided, pointers undecided) | whole-log escalation allowed and named in the verdict |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** grades are earned up the ladder, tape last.
- **Prove by:** the three fixtures above, run through the real `induct-grade` path.
- **Done when:** lying fixture blocks citing a pointer; clean fixture shows no whole-log read in its trace.

## Context

Added by owner decision during manual red-ink
(round 6 follow-up): the ladder was contract prose
in GOAL.md; this exp makes it machinery. Per the
standing rule, skill/workflow changes ride as an
experiment, not a direct edit.

## Tests

Known cases: Acceptance table fixtures; env-set
run-id is stamped by bp3 into the submit verdict
and ledger line (the mvp.1 mechanism).
Property-based:
for any seeded contradiction placed only at a rung-5
entry, the grade must not pass (generator: vary which
entry contradicts). Demos: fixture traces observed.
