---
date: 2026-11-17
goal: ../GOAL.md
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
before: docs/goals/<slug>/GOAL.md, quest/<slug> branch,
        /quest skill, goal_fin, "induct the quest"
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
  "docs/goals/": "docs/goals/", "GOAL.md": "GOAL.md",
  "quest/<slug>": "goal/<slug>", "goal_fin": "goal_fin",
  "goal_type": "goal_type", "/quest": "/goal (bp3 framing skill)",
  "induct-goal": "induct-goal", "red-ink-goal-landing-demo": "red-ink-goal-landing-demo",
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
## Amendment (owner, 2026-11-17): scope C — full rename with migration script

Owner escalated the purge from filenames to the
full surface, IDs included, with a migration
script doing the mechanical work:

| Surface | From | To |
|---|---|---|
| graph record | `QUEST.md` | `GRAPH.md` |
| node record | `EXPERIMENT.md` | `NODE.md` |
| folders | `docs/quests/`, `experiments/` | `docs/graphs/`, `nodes/` |
| node IDs | `exp-<milestone>-<n>-<slug>` | `node-<milestone>-<n>-<slug>` |
| node branches | `bp3/exp/<graph>/<node>` | per migration script's table |
| container term | quest | goal in prose; graph for structure |
| framing skill | `quest` (`/quest`) | `graph` (`/graph`) |
| conductor skill | `induct` | `traverse` |
| alias skill | `induct-quest` | deleted (was a pointer; old name refuses) |
| fleet skill | `induct-quest-no-human` | `traverse-no-human` |
| landing demo skill | `red-ink-quest-landing-demo` | `red-ink-graph-landing-demo` |

Skill acceptance adds: each new skill name loads;
each old name refuses/redirects (never a silent
duplicate body); renders for all harnesses
regenerated and freshness-checked.

Migration script requirements: dry-run mode
printing the full rename plan; idempotent
(second run is a no-op); refuses on a dirty
tree; renames branches without losing tips;
re-points every record reference in the same
change; ledger history lines are never edited
(old IDs inside landed ledger text stay, mapped
by the rename table). Acceptance adds: script
dry-run output quoted, post-migration state
reads for every pre-existing node return the
same state/commit under the new ID, and one
post-migration conduct completes with zero
rename-caused refusals.
