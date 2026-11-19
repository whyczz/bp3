# Audit notes — exp-followup-2-workflow-birth @ 6f124a6

Bound commit verified: `6f124a6 feat(followup.2): workflow-birth — desk reads, context, claim-session tape, render freshness`.
Graph read (rung 1) shows state handed_off, cycle 1, commit 6f124a6cfafb7427249e1f39442e8db648b106aa, 19 changed paths matching the commit stat.

Lessons:
- Render freshness is structural now: `bp3 skills check` byte-compares all four renders and refuses E_RENDER_STALE naming render+source; fresh is silent JSON ok. Live-probed: fresh ok, backdated bp3g-grade.js refused, restored ok; test/skills.sh passes (134 assertions).
- Desk reads and context threading are covered by mock-host fixtures in all four workflow test files (all pass). These prove prompt shape, not a real foreign-dialect conduct.
- Claim-session tape disambiguation is committed in src/graph/harness.ml with a harness.sh fixture, but the full test/harness.sh run exceeded the audit window (timed out), so that fixture is cited from committed code (rung 2), not an observed pass.
- No real node->grade->land conduct from a foreign-dialect root was run or fixtured; that Acceptance-addition case is missing, not passed on mock evidence.
- Working tree left clean; the stale-render probe was reverted with git checkout.

## Evidence matrix

```json
[
  {"case": "stale render at dispatch", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check with backdated .agents/workflows/bp3g-grade.js", "quote": "{\"ok\":false,\"error\":{\"code\":\"E_RENDER_STALE\",\"facts\":{\"stale\":[{\"workflow\":\"bp3g-grade\",\"render\":\".agents/workflows/bp3g-grade.js\",\"source\":\"skills/bp3g/workflows/bp3g-grade.js\"}]},\"guidance\":\"Re-render in the desk (./bin/bp3 skills install) and re-check; never launch a stale render.\"}}"}, "verdict": "pass"},
  {"case": "mvp.1 replay", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/skills.sh (backdated bp3g-grade render fixture, mvp.1 shape)", "quote": "skills tests: ok (134 assertions)"}, "verdict": "pass"},
  {"case": "fresh render", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check", "quote": "{\"ok\":true,\"fresh\":[\"node-loop\",\"bp3g-grade\",\"bp3g-land\",\"bp3g-node\"]}"}, "verdict": "pass"},
  {"case": "all three workflows", "rung": 2, "evidence": {"kind": "file", "ref": "bin/bp3 skills_check at 6f124a6", "quote": "local workflow_names=\"node-loop bp3g-grade bp3g-land bp3g-node\""}, "verdict": "pass"},
  {"case": "each defect has a regression fixture in the workflow tests", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs test/bp3g-land.test.mjs test/bp3g-node.test.mjs test/node-loop.test.mjs test/bp3g-conduct.test.mjs", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "full conduct (node -> grade -> land) from a foreign-dialect conductor root, zero read refusals", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-node.test.mjs (mock-host fixtures only; no real conduct run)", "quote": "bp3g-node tests: ok"}, "verdict": "missing"}
]
```
