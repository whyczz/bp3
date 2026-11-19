# Audit notes — exp-followup-3-goal-term-purge @ c0ab195

## Lessons

- Bound commit c0ab195 predates scope C: the Amendment (GRAPH.md/NODE.md/docs/graphs/node- IDs/migration script, skill renames to graph/traverse) landed in f8f75ce after the bound commit, so this audit grades only the 6 Acceptance cases present at c0ab195. Grading c0ab195 against scope C would fail work that was never asked of it.
- "quest" needs word boundaries: substring grep drowns in question/request. With `git grep -i -w`, code/skill/AGENTS surfaces are clean except the named legacy fold, but landed goal-record bodies under docs/goals still say Quest (78 files excl. runs/ledger/this record) — literal grep-zero fails as written; history scope is the open question for the owner.
- Two acceptance sub-clauses were already true before this commit (bp3g skill names from rename.1; no stale "no graph terms" rule text in naming at parent), so their bound-commit diffs are vocabulary syncs, not renames/removals. End state holds; credit is for state, not delta.
- Audit ran at HEAD 82446c8; src delta vs bound is only skills/bp3g/workflows/bp3g-grade.js, so the green `make check` (pipe-status 0) and live `bp3 g r` reads fairly corroborate the bound tree.
- No run-lifecycle derivation file exists for handoff run 20261117T155848Z (no 20261117 files in the derivations dir); conduct evidence rests on my own fresh read, not the derivation log.

## Matrix

```json
[
  {"case": "files renamed", "rung": 2, "evidence": {"kind": "command", "ref": "git ls-tree --name-only c0ab195fde5e12559ca72c71e1624e0b3c21bbf7 docs/goals/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/GOAL.md", "quote": "docs/goals/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/GOAL.md"}, "verdict": "pass"},
  {"case": "code renamed", "rung": 3, "evidence": {"kind": "command", "ref": "make check", "quote": "make-check-pipe-status:0"}, "verdict": "pass"},
  {"case": "skills renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 quest demo r parser-fix", "quote": "usage: bp3 init [--harness=<pi|claude|codex|muse|all>] | bp3 skills install [...] | bp3 skills check | bp3 g ... | bp3 n [r] | bp3 e [<edge> ...] | bp3 harness ... | bp3 harness desk derive|create|inspect|remove|prepare|check|exit|release|list ... | bp3 worktree ... (alias of harness desk) | bp3 config [--source] [--format json|table]"}, "verdict": "pass"},
  {"case": "grep proof", "rung": 3, "evidence": {"kind": "grep", "ref": "git grep -i -w -n quest c0ab195fde5e12559ca72c71e1624e0b3c21bbf7 -- docs/goals/ (excl **/runs/**, **/ledger.jsonl, excl exp-followup-3-goal-term-purge/EXPERIMENT.md)", "quote": "scheduling, and survives the Controller dying mid-flight. When this Quest"}, "verdict": "fail"},
  {"case": "conduct survives", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261117T171553Z-node-muse-code-muse-wonder-1.0-c1 ./bin/bp3 g r 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines", "quote": "exp-followup-3-goal-term-purge handed_off c0ab195fde5e12559ca72c71e1624e0b3c21bbf7"}, "verdict": "pass"},
  {"case": "terms synced", "rung": 2, "evidence": {"kind": "file", "ref": "skills/naming/SKILL.md:35 (at c0ab195fde5e12559ca72c71e1624e0b3c21bbf7)", "quote": "- Goal and graph: the container of work is a **goal** (`docs/goals/<goal>/GOAL.md`, `goal/<slug>` branch, finish word `goal_fin`); its DAG of nodes is the **graph** (`bp3 g` unchanged). Graph id/slug unchanged by the goal rename."}, "verdict": "pass"}
]
```
