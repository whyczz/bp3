# Audit notes — node-landing-1-landing-wrapup @ 71b87fa

Lessons: live rollup corroborates the scorecard exactly (18 nodes, 4 landed, 14 wall-null pre-rename, 18 wait-null) and `make check-fast` reruns green (exit 0); the honest `unmeasured` naming holds because no number lacks a source artifact. HEAD b9d7b3d is one evidence-only commit past the bound commit (run notes only, tracked diff otherwise empty). No whole-tape (rung 5) reads were needed; no derivation file exists for this run_id.

```json
[
  {"case": "scorecard complete", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 g 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines r | python3 -c count nodes/landed/wall_null/wait_null", "quote": "nodes 18"}, "verdict": "pass"},
  {"case": "findings dispositioned", "rung": 3, "evidence": {"kind": "command", "ref": "grep -c \"^| D\" runs/20261118T144757Z-handoff-muse-code-muse-wonder-1.0-c1/disposition.md", "quote": "12"}, "verdict": "pass"},
  {"case": "walkthrough run", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261118T145437Z-node-muse-code-muse-wonder-1.0-c1 ./bin/bp3 e", "quote": "\"source_rung\":\"session\""}, "verdict": "pass"},
  {"case": "diagrams included", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 g 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines diagram", "quote": "graph 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines diagram (generated from live state at 2026-11-18T14:55:16Z)"}, "verdict": "pass"}
]
```
