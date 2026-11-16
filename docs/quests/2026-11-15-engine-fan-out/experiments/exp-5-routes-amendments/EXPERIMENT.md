---
date: 2026-11-15
quest: ../../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Routes amendments mid-quest (follow-up)

## TL;DR

Follow-up from the red chair (2026-11-15): routes are
read from the branch tip, so they *can* change mid-quest
— this exp types what may change, so amendment is a
governed act instead of a silent rewrite. Rules:
**closed stages are immutable** (any diff touching a
landed member or a closed stage is `E_INVALID_ROUTES`);
the **open stage freezes at its first dispatch** (membership
and `paths` of the open stage cannot change while it is
open; a parked stage is still open); **future stages are
editable** by commit, and any amendment flips the file's
effective status back to `proposed` — dispatch pauses
until the owner re-approves (the amendment commit itself
carries `status: approved` only when the owner authors
it; the engine compares the routes file's hash against
the hash recorded at approval — approval records the
hash in the verdict, amendment changes it, Exp 1's
dispatch refusal does the rest). Reorder of future
stages, adding an exp to a future stage, and splitting a
future stage are all legal amendments; moving a member
between stages is legal only while both stages are
future.

## Demo (design trace)

```text
stage 1 closed, stage 2 open (one dispatch made), stage 3 future.
amendment: add exp-9 to stage 3        -> legal; status flips proposed; dispatch pauses
owner re-approves (status: approved)   -> dispatch resumes; stage 2 untouched
amendment: add exp-9 to stage 2        -> E_INVALID_ROUTES "open stage is frozen"
amendment: rename a landed exp in st.1 -> E_INVALID_ROUTES "closed stage is immutable"
```

## Diagram

```text
routes commit ─► diff vs approved routes ─► touches closed stage? ─► refuse
                                          ├─ touches open stage? ──► refuse
                                          └─ future only ─► status=proposed ─► owner re-approves ─► dispatch resumes
```

## Pseudocode

```python
def validate_amendment(old, new, states):
    for st in new.stages:
        if stage_state(st, states) == "closed" and st != old[st.stage]:
            refuse("closed stage is immutable", st.stage)
        if stage_state(st, states) == "open" and st != old[st.stage]:
            refuse("open stage is frozen", st.stage)
    return "proposed"        # any legal amendment re-opens approval
```

## Tables

| Field | Value |
|---|---|
| Intent | the plan can evolve without ever rewriting the past or the in-flight present |
| Lane | standard |
| Output | amendment validation in `src/quest/store.ml` (diff vs the last approved routes on the branch), approval-hash refusal in dispatch (`src/quest/main.ml`), fixtures in `test/q.sh` |
| Acceptance | cases below |
| Depends on | Exp 1 (validation), Exp 2 (dispatch exists to pause) |

| Case | Expected after |
|---|---|
| future-stage amendment | accepted as `proposed`; dispatch of the open stage **continues** (pause applies to the amended future stage's opening, not current work) |
| owner re-approval | dispatch of the amended stage opens when its turn comes |
| open-stage membership/`paths` edit | `E_INVALID_ROUTES`, named stage |
| closed-stage any edit | `E_INVALID_ROUTES`, named stage |
| move member between two future stages | legal amendment (re-approval required) |
| amendment while stage parked | future edits legal; the parked stage stays frozen until resumed and closed |
| no amendment | behavior identical to Exps 1–2 |

(Design decision recorded: an amendment does **not**
pause the currently open stage — pausing in-flight work
for a future-stage edit would make every plan tweak a
stop-work order. The pause is scoped to the amended
stages opening.)

## Acceptance test (goal block)

- **Objective:** routes can change mid-quest only in
  the future, and every change re-earns approval.
- **Prove by:** the traced amendments against a scratch
  quest in three stage states (closed/open/future),
  including the parked-stage variant; `make check` green.
- **Done when:** every refusal names its rule and stage,
  and legal amendments resume exactly at the amended
  stage's opening.

## Prose

Why freeze the open stage at first dispatch rather than
at stage opening: dispatch is the first moment another
actor (a child in a desk) holds the plan as ground
truth; changing membership after that strands a run
whose stage no longer contains it. Why approval is a
hash, not a flag the engine trusts blindly: the file
saying `approved` proves nothing about *which* file was
approved — the hash binds approval to content, and any
later byte changes it. This is the same lesson as
verdicts binding the exact commit reviewed, one level up.

## Tests

unit: none · fixtures: amendment matrix in `test/q.sh`
scratch quests · demos: the traces above at review
