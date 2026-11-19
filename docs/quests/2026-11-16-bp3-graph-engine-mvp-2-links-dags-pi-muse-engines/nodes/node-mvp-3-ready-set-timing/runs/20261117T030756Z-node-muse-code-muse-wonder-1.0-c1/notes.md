# exp-mvp-3-ready-set-timing — audit notes (run 20261117T030756Z-node-muse-code-muse-wonder-1.0-c1)

Bound commit: b765d076ad5aca6b322a95f193c15ae190825a9c
Build Run under audit: 20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1

## Lessons

- Rungs 1-3 decided every Acceptance case; no whole-tape read was needed (zero rung 5b). `bp3 harness find-tape --run-id <handoff>` timed out (EXIT:124 after 10s) and was not used as evidence.
- Ready/timing behavior is fully fixture-proved: `test/ready.sh` exercises diamond waves, cycle refusal, starved sets, hand-checked timing math (wait 600 / wall 2460), setup gate, and serial land against the real `bp3 q` binary; `test/induct-node.test.mjs` proves the one-terminal-outcome loop.
- Timing and setup are derived on read only — reads leave branch tips and the worktree untouched (asserted in test/ready.sh); setup lives in machine-local run configs, never in ledgers.
- Dep freeze is explored, not frozen: deps stay mutable-but-logged with state+cycle on the dep ledger line; the build notes propose requiring the reason to name the schedule change after `todo`, with no hard freeze justified yet.

## Matrix

```json
[
  {"case": "deps declared + cycle refused", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "ready-set waves correct", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "blocked blast radius", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "timing derived", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "setup measured", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "serial land", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "ready tests: ok"}, "verdict": "pass"},
  {"case": "dep freeze explored", "rung": 2, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/runs/20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Proposed rule from this evidence: keep deps mutable while `todo`; once a node leaves `todo`, a dep edit should require the reason to name the schedule change (as the test does) — a hard freeze is not justified yet; revisit if dogfood.2 shows a real mid-flight surprise."}, "verdict": "pass"},
  {"case": "node-worker shape", "rung": 3, "evidence": {"kind": "command", "ref": "node --test test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "env-set run-id (standing ruling)", "rung": 2, "evidence": {"kind": "ledger", "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-3-ready-set-timing:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/ledger.jsonl handoff line", "quote": "{\"ts\":\"2026-11-17T03:05:12Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"b765d076ad5aca6b322a95f193c15ae190825a9c\",\"verdict\":null,\"reason\":\"ready-set waves, node deps, derived timing, setup gate, induct-node loop; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1\"}"}, "verdict": "pass"},
  {"case": "adherence: handoff edge called by the child directly", "rung": 2, "evidence": {"kind": "ledger", "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-3-ready-set-timing:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/ledger.jsonl handoff line", "quote": "{\"ts\":\"2026-11-17T03:05:12Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"b765d076ad5aca6b322a95f193c15ae190825a9c\",\"verdict\":null,\"reason\":\"ready-set waves, node deps, derived timing, setup gate, induct-node loop; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1\"}"}, "verdict": "pass"},
  {"case": "adherence: env-set run-id stamped by bp3", "rung": 2, "evidence": {"kind": "ledger", "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-3-ready-set-timing:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/ledger.jsonl handoff line", "quote": "{\"ts\":\"2026-11-17T03:05:12Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"b765d076ad5aca6b322a95f193c15ae190825a9c\",\"verdict\":null,\"reason\":\"ready-set waves, node deps, derived timing, setup gate, induct-node loop; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1\"}"}, "verdict": "pass"},
  {"case": "adherence: clean commit", "rung": 2, "evidence": {"kind": "command", "ref": "git show -s --format=\"%H %an %s\" b765d076ad5aca6b322a95f193c15ae190825a9c; git status --porcelain (empty)", "quote": "b765d076ad5aca6b322a95f193c15ae190825a9c whycz feat(mvp.3): ready-set waves, node deps, derived timing, setup gate, induct-node loop"}, "verdict": "pass"},
  {"case": "adherence: tape.log and notes.md present in its run folder", "rung": 2, "evidence": {"kind": "command", "ref": "ls docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-3-ready-set-timing/runs/20261117T013825Z-handoff-muse-code-muse-wonder-1.0-c1/", "quote": "notes.md tape.log"}, "verdict": "pass"},
  {"case": "adherence: no hand-edited state", "rung": 2, "evidence": {"kind": "command", "ref": "git status --porcelain at b765d076ad5aca6b322a95f193c15ae190825a9c", "quote": ""}, "verdict": "pass"}
]
```
