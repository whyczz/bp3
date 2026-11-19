# Audit notes — exp-followup-2-workflow-birth @ e37190a (cycle 2)

Bound commit verified: `e37190aad4bb73183af2f433a92ff325eef6c3ec` (HEAD matches). Node read (rung 1): state handed_off, cycle 2, commit e37190a, single added path conduct-cycle2.md. Product commit 6f124a6 implements all four birth defects; cycle-2 commit adds only the real-conduct proof.

Lessons:
- Cycle 2 closes the one gated gap from the 6f124a6 grade: a REAL foreign-dialect conduct (fixture graph landed, 0 of 6 read refusals) now backs the deskNote claim. Independently re-verified: fixture read via desk binary with BP3_G_BIN returns landed/node_fin at fafcc14; root binary answers the same read with old-dialect usage.
- Freshness held under live probe: fresh check ok, backdated bp3g-grade render refused E_RENDER_STALE naming render+source, restored fresh ok; test/skills.sh passes (134 assertions). Working tree left clean apart from untracked .bp3-context.json.
- harness.sh passes in full this cycle (all checks passed), including the claim-session find-tape fixture — stronger than cycle 1, where it timed out and was cited from code only.
- Caveats from conduct-cycle2.md stand (single-session sequential conduct, W_CONTEXT_ENV_MISMATCH stamp, BP3_G_BIN workaround for fresh desks) but do not touch the graded claim: no read was refused and the state sequence is exact.

## Evidence matrix

```json
[
  {"case": "stale render at dispatch", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check with backdated .agents/workflows/bp3g-grade.js", "quote": "{\"ok\":false,\"error\":{\"code\":\"E_RENDER_STALE\",\"facts\":{\"stale\":[{\"workflow\":\"bp3g-grade\",\"render\":\".agents/workflows/bp3g-grade.js\",\"source\":\"skills/bp3g/workflows/bp3g-grade.js\"}]},\"guidance\":\"Re-render in the desk (./bin/bp3 skills install) and re-check; never launch a stale render.\"}}"}, "verdict": "pass"},
  {"case": "mvp.1 replay", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/skills.sh (backdated bp3g-grade render fixture, mvp.1 shape)", "quote": "skills tests: ok (134 assertions)"}, "verdict": "pass"},
  {"case": "fresh render", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check", "quote": "{\"ok\":true,\"fresh\":[\"node-loop\",\"bp3g-grade\",\"bp3g-land\",\"bp3g-node\"]}"}, "verdict": "pass"},
  {"case": "all three workflows", "rung": 2, "evidence": {"kind": "file", "ref": "bin/bp3 skills_check at e37190a", "quote": "local workflow_names=\"node-loop bp3g-grade bp3g-land bp3g-node\""}, "verdict": "pass"},
  {"case": "each defect has a regression fixture in the workflow tests", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs test/bp3g-land.test.mjs test/bp3g-node.test.mjs test/node-loop.test.mjs test/bp3g-conduct.test.mjs; bash test/harness.sh", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "full conduct (node -> grade -> land) from a foreign-dialect conductor root, zero read refusals", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_G_BIN=<graph-worktree main.exe> ./bin/bp3 g 2026-11-17-followup2-fixture r exp-fixture-trivial (fixture desk)", "quote": "{\"ok\":true,\"graph\":\"2026-11-17-followup2-fixture\",\"node\":\"exp-fixture-trivial\",\"state\":\"landed\",\"fin\":\"node_fin\",\"cycle\":1,\"commit\":\"fafcc145933c37a38fac5125539f6cb06ca5c59e\"}"}, "verdict": "pass"}
]
```
