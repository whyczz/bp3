# exp-mvp-3-ready-set-timing — audit notes (run 20261117T042227Z-node-muse-code-muse-wonder-1.0-c2)

Bound commit: 105cbea174e8b204413cf2428aea78eec2e344d0

## Lessons

- Rungs 1-3 decided every Acceptance case; zero whole-tape reads (no rung 5b). mvp.3 files are unchanged between bound commit 105cbea and HEAD 8411e0a, so tests run at HEAD represent the bound commit.
- `test/ready.sh` proves deps/cycle/waves/starved/timing/setup/serial-land against the real `bp3 q` binary; `test/induct-node.test.mjs` proves the one-terminal-outcome loop. Timing/setup are derived on read only.
- Dep freeze is explored, not frozen: mid-flight dep edit stays logged with state+cycle; handoff notes propose requiring the reason to name the schedule change after `todo`, with no hard freeze justified yet.

## Matrix

```json
[
  {"case": "deps declared + cycle refused", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "ready-set waves correct", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "blocked blast radius", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "timing derived", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "timing read clean: tip unchanged, worktree entries: 0"}, "verdict": "pass"},
  {"case": "setup measured", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "serial land", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "dep freeze explored", "rung": 2, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/runs/20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "once a node leaves `todo`, a dep edit should require the reason to name the schedule change (as the test does) — a hard freeze is not justified yet; revisit if dogfood.2 shows a real mid-flight surprise."}, "verdict": "pass"},
  {"case": "node-worker shape", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "env-set run-id (standing ruling)", "rung": 2, "evidence": {"kind": "ledger", "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-3-ready-set-timing:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/ledger.jsonl handoff line cycle 2", "quote": "{\"ts\":\"2026-11-17T03:37:05Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":2,\"commit\":\"105cbea174e8b204413cf2428aea78eec2e344d0\",\"verdict\":null,\"reason\":\"cycle 2: quotable no-hand-edited-state guard + typed evidence; ready/induct/lint green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T032158Z-handoff-muse-code-muse-wonder-1.0-c2\"}"}, "verdict": "pass"}
]
```
