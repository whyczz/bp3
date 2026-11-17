---
date: 2026-11-17
goal: ../GRAPH.md
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
before: docs/graphs/<slug>/GRAPH.md, quest/<slug> branch,
        /quest skill, goal_fin, "induct the quest"
after:  docs/graphs/<slug>/GRAPH.md, goal/<slug> branch,
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
  "docs/graphs/": "docs/graphs/", "GOAL.md": "GOAL.md",
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
| files renamed | `docs/graphs/<slug>/GRAPH.md` live; graph id/slug unchanged; no path a record points at is broken (exp records re-pointed in the same commit) |
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

## Fix ledger (append-only)

- 2026-11-17 · cycle 2 · from grade of c0ab195 (blocked) · status: open
  fix: "grep proof fails: 671 quest hits on live docs/goals at bound commit, first GOAL.md:11 — scope grep-zero to live surfaces (code, skills, CLI, this graph's live docs); exempt by name: other graphs' historical records, dated amendments, landed ledger text (owner A at blocked gate). Cycle 2 also delivers scope C: migration script (dry-run, idempotent, refuses dirty tree), GRAPH.md/NODE.md, nodes/ folders, node- IDs, skill renames /graph, traverse, traverse-no-human, red-ink-graph-landing-demo."
  regression_test: none named (existing make check + grep proof)

## Grep scope (cycle 2, owner A at blocked gate)

Grep-zero (`-i -w`) binds live surfaces only: code
(`src/`, `bin/`, `scripts/`, `extensions/`), skills
(`skills/` + harness renders), CLI help/usage text,
and this graph's live docs (its GRAPH.md and
NODE.md records). Exempt by name: other graphs'
historical records under docs/graphs/, dated
amendments (including the Amendment above), landed
ledger text (ledger.jsonl lines and this record's
history quotes), the one-place legacy fold in
src/graph/store.ml, the migration script's own
rename table, and negative-absence assertions in
tests (an old name that must refuse).
- 2026-11-17 · cycle 2 · RESOLVED (this handoff)
  resolution: "Grep-zero scoped to live surfaces (code, skills, CLI, this graph's live docs): 0 hits excluding runs/ledger/this record; exemptions named in '## Grep scope (cycle 2)'. Scope C delivered by scripts/migrate-graph-rename.sh (dry-run plan quoted in run tape; apply on clean tree; second run no-op): GRAPH.md/NODE.md, docs/graphs + nodes/ folders, node- IDs, bp3/graph + bp3/node refs, work branches graph/<slug>, tips preserved, references re-pointed, ledger.jsonl 100% renames (0 content changes). Engine fold in src/graph/store.ml maps legacy refs/paths/IDs on read. Skill names: bp3g family is the settled conducting family (test/skills.sh asserts old quest/induct/traverse names render nowhere); renders regenerated via bp3 skills install. Post-migration: all 18 nodes of this graph read back same state/commit/cycle under new IDs, make check green, conduct reads ok with zero rename-caused refusals."

- 2026-11-17 · cycle 3 · from grade of bd58f82 (blocked) · status: open
  fix: "gated adherence fails: (1) git status shows system residue — bind-tape's post-handoff tape.log append plus regenerated .bp3-context.json; owner: runs/tape/context are runtime output and must be gitignored so git status is clean after any step, committed evidence stays deliberate (notes.md). (2) grade probe resolves the handoff ledger line via the retired bp3/exp/ branch hardcode; branches are bp3/graph/ now — resolve via the desk binary's post-migration scheme. Then re-handoff from a clean tree via the claimed child path so the handoff ledger line carries the stamped run-id. Keep a regression test with the project for both fixes (workflow tests for probe resolution; a cleanliness fixture asserting git status stays empty across a step)."
  regression_test: workflow tests (probe resolution) + cleanliness fixture, kept in test/
