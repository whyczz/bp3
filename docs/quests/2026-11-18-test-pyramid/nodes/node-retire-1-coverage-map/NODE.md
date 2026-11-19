---
date: 2026-11-18
quest: ../../QUEST.md
node: retire.1
status: proposed
---

# retire.1 - coverage-map: delete old suites only with proof

## TL;DR

Every old suite gets rows in `test/COVERAGE.md`, one per assertion
cluster, each naming its new home (a unit test, a fixture,
or a slow proof) or the reason it stays. Before any deletion, a
mutation table (`test/MUTATIONS.md`) plants engine bugs and records
which tiers catch them. A suite is deleted only when no row reads
old caught, new missed. New tests land first; deletions land in a
separate commit after the owner reads both tables.

## Acceptance gates

Design trace (nothing has run):

```text
test/COVERAGE.md
| suite   | cluster                         | new home                                  |
| g.sh    | quest create refuses a bad slug | unit: law_valid_slug_rejects_...          |
| g.sh    | node handoff binds the commit   | fixture: q-door                           |
| harness | claim race: one winner          | slow: harness-race (kept, budget 20s)     |

test/MUTATIONS.md
| mutation                                  | old | new |
| fold_state_name drops "submitted"         | yes | yes |
| stale gate uses >= instead of >           | no  | yes |
| legal_edges allows land from handed_off   | yes | yes |
```

```yaml
objective: shrink the slow suites without losing any behavior they pinned
prove by:
  - test/COVERAGE.md rows for every suite in the 2026-11-18 profile   # file absent today
  - test/MUTATIONS.md: at least 10 planted mutations, each run against the old suites and the new tiers
  - make check-full timing after the deletions
done when:
  - every old suite is either deleted with every cluster mapped, or kept with a one-line reason
  - no mutation row reads old caught, new missed
  - new tests land in commits before the deletion commit; the grader runs both on the pre-deletion commit
  - the owner has read COVERAGE.md and MUTATIONS.md before the deletion commit
  - make check-full stays at 60s or less, five runs in a row
```

## Diagram

```text
old suite ─► clusters ─► COVERAGE.md row ─► new home exists and is green?
                                                │ yes
mutations ─► run old ─► run new ─► MUTATIONS.md ─► any (old yes, new no)? ─► block
                                                │ none
                                   owner reads ─► deletion commit
```

## Pseudocode

```python
for suite in OLD_SUITES:
    for cluster in clusters(suite):
        row = COVERAGE[suite, cluster]
        assert row.kept_reason or test_exists_and_green(row.new_home)
for m in MUTATIONS:                                  # >= 10, planted and reverted
    m.old = caught(apply(m), OLD_SUITES); m.new = caught(apply(m), NEW_TIERS)
assert not any(m.old and not m.new for m in MUTATIONS)
owner_reads(COVERAGE, MUTATIONS); commit_deletions()
```

| Field | Value |
|---|---|
| Intent | retire slow suites with evidence that nothing was lost |
| Lane | high-blast-radius (deletes tests) |
| Output | `test/COVERAGE.md`, `test/MUTATIONS.md`, new fixtures, deletion commit |
| Acceptance | goal block above; fails today (no map, no mutation table) |
| Depends on | tier.2, unit.3, unit.4, js.1 |
| Tests | known cases: the fixture and slow suites written here, and one row per mutation; property-based: none, by decision: the mutation table is the breadth check |

Substeps (each passes on its own):

| Substep | Scope |
|---|---|
| retire.1.1 | map and mutation baseline over every old suite; no deletions |
| retire.1.2 | engine suites: g, ready, diagram, blocked, config, mode, context, completion |
| retire.1.3 | process suites: harness, link, worktree, hooks, tape, dogfood-link, dogfood-parallel |
| retire.1.4 | the rest: skills, cleanliness, release, install, pi-tree (kept slow unless mapped) |

## Prose

The red chair's fourth concern drives this node's shape: the agent
writing new tests also deletes old ones, which is the
reward-hacking setup the 11-14 references warned about. Three
guards answer it: the mutation table is evidence a grader can rerun,
new tests and deletions are separate commits, and the owner reads the
tables before anything is deleted.

Mutations are planted in a scratch worktree and reverted. They never
land. Each row names the file, the one-line change, and the command
that caught it. Ten is a floor: at least one per function family in
unit.3 and unit.4, plus the harness claim race, the run-id mint, and
the stale gate.

Some suites will stay. pi-tree proves a real process tree, which no
unit test can. A kept suite moves to the slow tier when it meets the real-process
rule (red-ink R7), with a budget and a one-line `why`; otherwise it
stays a fixture.
