---
date: 2026-11-17
quest: ../QUEST.md
exp: followup.5
status: proposed
---

# followup.5 - pure-grade: the grader computes, the looper applies

## TL;DR

Owner decision (2026-11-17): the grader is a
pure function — `grade(commit, node_record) ->
Verdict` — and writes nothing. All effects live
in the looper/conductor: one verdict cast,
fix-ledger entries, dispatch. Today the grade
and verify children both cast and the second
eats `E_ILLEGAL_EDGE` (the "expected verdict
race" on followup.1/followup.2 grades), and the
audit child holds the state pen during its own
audit. This node splits compute from effect and
gives the looper named pushback/escalation
paths instead of silent retries.

## Demo (design trace)

```text
before: grade child audits AND casts; verify child casts again -> E_ILLEGAL_EDGE race
after:  audit/verify children return verdicts (zero bp3 g u calls)
        looper: checks -> casts ONCE -> ledgers fix -> dispatches author
        looper pushback: superseded commit / empty fix / blocked state -> named refusal
```

## Diagram

```text
audit ─┐
       ├─► Verdict (data) ─► looper.apply ─┬─ cast once (bp3 g u)
verify ┘        pure                      ├─ fix-ledger OPEN entry (verbatim) + commit
                                          ├─ dispatch author (context = fix)
                                          └─ pushback: named refusal / escalate owner
author: code + RESOLVED entry in its fix commit; grader never edits the record
```

## Pseudocode

```python
def grade(commit, record) -> Verdict: ...      # no writes, replayable

def apply(verdict, read):
    if verdict.commit != read.commit: return refuse("superseded - re-grade")
    if verdict.outcome == "needs_fix" and not verdict.fix: return escalate("empty fix")
    if read.state == "blocked": return escalate("owner gate")
    cast_once(verdict); ledger_open(verdict.fix); dispatch_author(context=verdict.fix)
```

| Field | Value |
|---|---|
| Intent | a killed or disbelieved grade leaves zero writes behind |
| Lane | standard |
| Output | return-only audit children, single-cast applier, named looper pushback |
| Depends on | followup.3 (renames first; workflows change once, in final vocabulary) |

## Acceptance

| Case | Expected |
|---|---|
| pure audit | audit/verify children make zero `bp3 g u` calls (tape grep evidence) |
| single cast | exactly one verdict cast per grade; the verdict-race refusal no longer occurs in the workflow fixtures |
| safe replay | a grade killed mid-run, re-dispatched on the same commit, leaves no partial writes (state read before/after) |
| pushback: superseded | verdict naming a non-current commit is refused by name; no cast attempted |
| pushback: empty fix | `needs_fix` with no fix text escalates (named) instead of dispatching an author |
| pushback: blocked | a cast attempted over a `blocked` read escalates to the owner gate; state untouched |
| fix ledger live | one real `needs_fix` cycle runs: OPEN entry (conductor) → author fix → RESOLVED entry (author commit) → grade verifies |
| regression | workflow tests cover cast-once + all three pushbacks; `make check` green |

## Acceptance test (goal block)

- **Objective:** grade computes, looper applies,
  nobody else writes.
- **Prove by:** tape greps, cast counts, pushback
  fixtures, one live ledgered cycle.
- **Done when:** a full grade runs with a single
  cast and the race refusal is gone.

## Tests

Workflow unit fixtures for return-only children,
single cast, and the three pushbacks; `make check`.

## Context

Owner: "we're keeping the grader as a pure
function, e.g. commit + exp/node => looper
writes" — "the node looper can push back,
escalate, etc, okay let's lock that in."
Fix-ledger convention (in the node record,
append-only): OPEN by conductor, RESOLVED by
author in its fix commit, verified by grader.
Not the killed followup.4: no typed payload
schema; the fix stays verbatim text.
