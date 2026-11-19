# Audit lessons — node-followup-3-goal-term-purge @ 18f7823 (run 20261117T224032Z-node-muse-code-muse-wonder-1.0-c3)

- Claimed link bp3link_ac4f0cd3d522daa35323972ab72d5d1d; returned run_id matched the expected folder name. Run folder did not pre-exist.
- Cycle-4 record fixes verified at rung 2: GRAPH.md carries zero `experiments/` refs and all 18 `nodes/node-*/NODE.md` record links resolve on disk; AGENTS.md carries zero `GOAL.md` refs (Layout/status now say GRAPH.md).
- Full `make check` was observed green in this run (make exit:0, including skills, cleanliness, bp3g-grade suites); post-purge conduct reads back `handed_off` at the bound commit under the new node ID with this run's stamped run_id and zero rename-caused refusals.
- Scoped grep-zero holds only under the exemptions named in NODE.md's Grep scope (store.ml legacy fold, migration rename table, naming frozen-spelling note, this record's history); unscoped greps fail by design.
- Remaining defect is narrow and at rung 2: the naming skill still names the graph record `GOAL.md` (skills/naming/SKILL.md:39) although the live file is GRAPH.md — the same lag the cycle-2 audit flagged in naming; cycle 4 fixed AGENTS.md only. Terms therefore still fail on the naming surface.

## Evidence matrix

```json
[
  {"case": "files renamed", "rung": 2, "evidence": {"kind": "command", "ref": "link existence sweep over GRAPH.md record links (bound commit 18f7823)", "quote": "links ok=18 bad=0"}, "verdict": "pass"},
  {"case": "code renamed", "rung": 3, "evidence": {"kind": "command", "ref": "make check (full, bound commit 18f7823)", "quote": "make exit:0"}, "verdict": "pass"},
  {"case": "skills renamed", "rung": 3, "evidence": {"kind": "command", "ref": "grep -H ^name: skills/bp3g*/SKILL.md; old quest/induct/traverse dirs absent (make check skills suite green)", "quote": "skills/bp3g-frame/SKILL.md:name: bp3g-frame"}, "verdict": "pass"},
  {"case": "grep proof", "rung": 3, "evidence": {"kind": "command", "ref": "grep -rniw quest src/ bin/ scripts/ extensions/ skills/ | grep -v src/graph/store.ml | grep -v migrate-graph-rename | grep -v skills/naming/SKILL.md", "quote": "scoped exit:1 (1=zero)"}, "verdict": "pass"},
  {"case": "conduct survives", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261117T224032Z-node-muse-code-muse-wonder-1.0-c3 ./bin/bp3 g 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines n node-followup-3-goal-term-purge r", "quote": "\"state\":\"handed_off\",\"cycle\":3,\"commit\":\"18f78233908d9fad6bfdc7a32a0c06652d6784db\""}, "verdict": "pass"},
  {"case": "terms synced", "rung": 2, "evidence": {"kind": "file", "ref": "skills/naming/SKILL.md:39", "quote": "- Artifacts: GOAL.md, state.yaml, ledger.jsonl,"}, "verdict": "fail"},
  {"case": "migration script (Amendment scope C)", "rung": 3, "evidence": {"kind": "command", "ref": "bash scripts/migrate-graph-rename.sh --dry-run", "quote": "migrate-graph-rename: dry-run complete (idempotent: re-run is a no-op)"}, "verdict": "pass"}
]
```
