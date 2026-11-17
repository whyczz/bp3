# Audit notes — exp-mvp-5-blocked-fail-fast @ f5b434d

Brief lessons:
- Bound commit f5b434d adds test/pi-tree.test.mjs (real Pi root -> node-worker -> edge-worker processes); prior 4d00100 adds blocked-fail-fast in induct-node and test/blocked.sh.
- Rung 3 runs: ./test/blocked.sh passed, node test/induct-node.test.mjs passed, node test/pi-tree.test.mjs passed on second run.
- First pi-tree run failed one assertion verbatim: FAIL: watch dispositions grandchild orphaned: {"ok":false,"error":{"code":"E_NOT_FOUND","facts":{"run_id":"20261117T055520Z-handoff-pi-test-model-c1"},"guidance":"No tape references that run; no guess made."}} — second run passed (pi-tree tests: ok); treat unreaped-grandchild proof as flaky/racy, not stable.
- No derivation log existed for this audit run at <git-common-dir>/bp3/run-lifecycle-derivations/20261117T055441Z-node-muse-code-muse-wonder-1.0-c2.jsonl (ls: No such file or directory); no corroboration taken from it.
- No whole-tape (rung 5b) read was used; all rows decided at rung 3.
- Cycle-cap live page is the conductor presenting the single inbox entry in the main session (skills/traverse/SKILL.md Blocked gate); automated proof covers blocked+exit+exactly-one inbox, page presentation itself is procedural.

Matrix:
```json
[
  {"case": "edge completes", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "Pi tree bubbles to root", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "whole Pi tree dies", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "Pi revival is a fresh tree", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "unreaped Pi grandchild", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "root Pi session dies", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "edge returns typed failure", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "`needs_fix` below cycle cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "cycle cap exceeded", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "human decision required", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "human answers", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "stale worker returns after block", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "edge worker dies silently", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "sibling nodes are ready", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "conductor restarts", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"}
]
```
