---
date: 2026-11-17
quest: ../QUEST.md
exp: followup.3
status: proposed
---

# followup.3 - goal-term-purge: quest is gone, the word is goal

## TL;DR

Owner decision (2026-11-17): the term `quest`
is deleted from bp3's vocabulary. The container
of work is a **goal**; its DAG of nodes is the
graph (`bp3 g` already speaks graph/node). This
node performs the purge on every live surface —
files, code, skills, docs — the same way
rename.1 purged the old CLI nouns. Ledger
history is history: landed ledger lines keep
the words they were written with.

## Demo (design trace)

```text
before: docs/quests/<slug>/QUEST.md, quest/<slug> branch,
        /quest skill, quest_fin, "induct the quest"
after:  docs/goals/<slug>/GOAL.md, goal/<slug> branch,
        /goal framing skill, goal_fin, "induct the goal"
        bp3 g <goal> r <node>  (graph door unchanged)
```

## Diagram

```text
term quest ──purge──► term goal        (container, files, skills, reports)
term graph ──stays──► the goal's DAG   (bp3 g, node, edge, dep: unchanged)
ledger history ──stays──► old words in landed lines (never rewritten)
```

## Pseudocode

```python
RENAME = {
  "docs/quests/": "docs/goals/", "QUEST.md": "GOAL.md",
  "quest/<slug>": "goal/<slug>", "quest_fin": "goal_fin",
  "quest_type": "goal_type", "/quest": "/goal (bp3 framing skill)",
  "induct-quest": "induct-goal", "red-ink-quest-landing-demo": "red-ink-goal-landing-demo",
}
for surface in live_surfaces: apply(RENAME, surface)
assert grep("quest", live_surfaces) == 0   # history/ledger exempt, named
```

| Field | Value |
|---|---|
| Intent | one concept, one word, one spelling, everywhere |
| Lane | standard |
| Output | goal vocabulary on all live surfaces; rename table in Terms; grep-zero proof |
| Depends on | rename.1, followup.2 (conduct must survive the rename) |

## Acceptance

| Case | Expected |
|---|---|
| files renamed | `docs/goals/<slug>/GOAL.md` live; graph id/slug unchanged; no path a record points at is broken (exp records re-pointed in the same commit) |
| code renamed | `quest` identifiers on live code surfaces renamed (dirs/modules/verbs per rename table); `make check` green |
| skills renamed | framing/induct/landing-demo skills answer to goal names; old skill names refuse or redirect, never silently duplicate |
| grep proof | `quest` (case-insensitive) greps to zero on live surfaces; exemptions listed by name (landed ledger text, this record's history quotes) |
| conduct survives | after the purge, one node is conducted (read → handoff or land) with zero refusals caused by the rename |
| terms synced | QUEST/GOAL Terms, AGENTS.md, naming skill vocabulary all say goal; naming skill's stale "no graph terms" rule removed |

## Acceptance test (goal block)

- **Objective:** no live surface says quest.
- **Prove by:** grep-zero output + `make check` + one post-purge conduct.
- **Done when:** the graph reads, lands, and reports in goal vocabulary only.

## Tests

`make check`; targeted greps from the acceptance
table; fixture conduct of one already-landed node
(read-only) plus the next live node's first step.

## Context

Owner: "the term quest gone, it should be goal"
then confirmed quest→goal in files and code.
`goal` names the destination; `graph` names the
machine that gets there. rename.1 proved a live
rename is safe in this engine; this is the same
move on the last old noun.
