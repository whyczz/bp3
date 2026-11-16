---
date: 2026-11-15
quest: ../../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — Integration order at `quest_fin` (follow-up)

## TL;DR

Follow-up from the red chair (2026-11-15): parallel
members land as N content commits on N branches, and
nothing owned putting them together. This exp makes
routes order the integration contract: at `quest_fin`,
the landing ceremony applies member commits in **stage
order, then routes-listed member order** — never
completion order — via cherry-pick onto the promotion
target, one member at a time, each result checked
(`make check` per member is too slow; one gate at the
end, plus a clean-tree assertion per pick). A pick that
conflicts stops the ceremony, names the member and the
member it conflicts with, and parks: already-applied
picks stay (they are clean), the conflicting member
returns to its owner as a named decision, and no silent
merge resolution is ever attempted.

## Demo (design trace)

```text
routes [[A, B], [C]]; completion order was B, A, C.
quest_fin integration:
  pick A (stage 1, listed 1st)  -> clean
  pick B (stage 1, listed 2nd)  -> CONFLICT with A on src/quest/main.ml
  -> ceremony parks: "B conflicts with A (applied); B is owed a rebase decision"
     C never attempted. Applied: [A]. Parked: [B]. Untouched: [C].
```

Observed seed: in the serial era this never bit, because
content commits stacked on one branch by habit
(bp3-cli-small-fixes Exps 1–3 on master). The parallel
dogfood (demo-routes, 2026-11-15) landed two members on
separate exp branches with disjoint files — clean by
construction, which is exactly the case that hides the
missing contract.

## Diagram

```text
quest_fin ─► for stage in routes: for member in listed order:
               cherry-pick member.commit ─► clean? ─► next
                                            └ conflict ─► park(member, conflicts_with=last applied on that path)
             all applied ─► make check ─► promotion proceeds (owner gate, unchanged)
```

## Pseudocode

```python
def integrate(quest, target):
    applied = []
    for member in routes_order(quest):            # stage, then listed order
        r = cherry_pick(member.commit, onto=target)
        if r.conflict:
            return park(member=member, conflicts_with=blame(applied, r.paths), applied=applied)
        applied.append(member)
    run("make check")
    return applied
```

## Tables

| Field | Value |
|---|---|
| Intent | a parallel quest promotes as deterministically as a serial one |
| Lane | standard |
| Output | integration step in `skills/induct/workflows/quest-land.js` (ceremony extension) + `test/land-integration.sh` fixture |
| Acceptance | cases below |
| Depends on | Exp 2 (groupwise landings exist to integrate) |

| Case | Expected after |
|---|---|
| disjoint members, scrambled completion order | integration applies in routes order; final tree equals the routes-order expectation, not completion order |
| conflicting member | ceremony parks naming member + conflicting applied member + paths; later members unattempted; applied picks remain |
| conflict resolved by owner (rebase commit submitted, re-landed) | ceremony resumes from the parked member, does not re-apply earlier picks |
| serial quest (no routes / singleton stages) | integration is today's promotion, unchanged |
| `make check` red after all picks | promotion stops before merge; the applied picks are listed as the suspect set |

## Acceptance test (goal block)

- **Objective:** `quest_fin` integration is ordered,
  deterministic, and parks honestly on conflict.
- **Prove by:** `test/land-integration.sh` scratch quest
  with two members editing the same file (engineered
  conflict) and a disjoint control pair; resume trace
  after a fix commit; `make check` green.
- **Done when:** order, park, and resume traces match,
  and the serial control promotes identically to today.

## Prose

Why cherry-pick in routes order instead of merging exp
branches: merges would import ledger branches' histories
into the promotion target and make order implicit in
merge topology; picks keep one linear, reviewable
sequence whose order a human already approved in the
routes file. Why the ceremony may leave partial picks
applied: each pick is independently clean and gated;
rewinding clean work to pretend atomicity would hide
which member actually conflicts. The park names a member
pair, because "merge conflict in main.ml" is weather,
but "B's change assumes A's old shape" is a decision.

## Tests

unit: none · fixtures: `test/land-integration.sh`
(conflict pair, disjoint pair, resume, serial control) ·
demos: the design trace on a scratch quest at review
