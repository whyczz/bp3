# Audit lessons — node-followup-3-goal-term-purge @ 7382b94 (run 20261117T214440Z-node-muse-code-muse-wonder-1.0-c2)

- Claimed link bp3link_e8a9f3f6926970383d60881bf7c358bf; returned run_id matched the expected folder name. Run folder did not pre-exist.
- Decisive defect is at rung 2, not the tape: GRAPH.md still carries 17 relative record links of the form `experiments/exp-<...>/NODE.md` (e.g. line 685 for this very node). Those paths do not exist; live records are `nodes/node-<...>/NODE.md`. The engine reads by folder scan, so `bp3 g r` works and masks the broken record pointers.
- Terms are not fully synced: AGENTS.md Layout and the naming skill still name the graph record `GOAL.md` (actual file: GRAPH.md), and two bp3g skill bodies still say `EXPERIMENT.md`. Container vocabulary (goal/graph) is correct; the file-name vocabulary lagged the rename.
- Scoped grep-zero holds only under the exemptions named in NODE.md's Grep scope (store.ml legacy fold, migration rename table, naming frozen-spelling note, this record's history). Unscoped greps will always "fail" this node by design.
- Aggregate `make check` exceeded two 240–270s foreground budgets in test/ready.sh territory; its constituent suites (g, ready, skills, cleanliness, bp3g-grade) each pass standalone. I did not observe a full `make check` green run in this audit and do not claim one.
- Post-migration conduct is real: node read under the new ID returns state handed_off at the bound commit with this run's stamped run_id and zero rename-caused refusals.

## Evidence matrix

```json
[
  {"case": "files renamed", "rung": 2, "evidence": {"kind": "grep", "ref": "docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/GRAPH.md:685", "quote": "### followup.3 - goal-term-purge — [record](experiments/exp-followup-3-goal-term-purge/NODE.md)"}, "verdict": "fail"},
  {"case": "code renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./test/g.sh; ./test/ready.sh (via make check constituents)", "quote": "g tests: ok"}, "verdict": "pass"},
  {"case": "skills renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-skills skills .pi/skills .agents/skills .claude/skills; ./test/skills.sh", "quote": "skills check: ok (40 files)"}, "verdict": "pass"},
  {"case": "grep proof", "rung": 3, "evidence": {"kind": "command", "ref": "grep -riw quest src/ bin/ scripts/ extensions/ skills/ | grep -v src/graph/store.ml | grep -v migrate-graph-rename | grep -v skills/naming/SKILL.md", "quote": "scoped grep exit:1 (1=zero)"}, "verdict": "pass"},
  {"case": "conduct survives", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261117T214440Z-node-muse-code-muse-wonder-1.0-c2 ./bin/bp3 g 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines r node-followup-3-goal-term-purge", "quote": "\"state\":\"handed_off\",\"cycle\":2,\"commit\":\"7382b940a14c1bec6e5d1655fb5ef32aeb9fe10a\""}, "verdict": "pass"},
  {"case": "terms synced", "rung": 2, "evidence": {"kind": "file", "ref": "AGENTS.md Layout (bound commit 7382b94)", "quote": "  GOAL.md               authored: goal, scope, nodes, status field"}, "verdict": "fail"},
  {"case": "migration script (Amendment scope C)", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/migrate-graph-rename.sh --dry-run", "quote": "migrate-graph-rename: dry-run complete (idempotent: re-run is a no-op)"}, "verdict": "pass"}
]
```
