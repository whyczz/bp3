# Audit notes — node-dogfood-3-external-drive @ ac43954

Lessons: derived mode holds live in both habitats — self here, host in /tmp/flappy-bird with core-only skills and bare-`bp3` hooks; the flappy node is landed at 21fb9de with smoke green and zero bp3 source in its tree. `test/mode.sh` (49 assertions) and full `make check` (exit 0) both rerun green at the bound commit. No whole-tape (rung 5) reads were needed.

```json
[
  {"case": "mode derives host", "rung": 3, "evidence": {"kind": "command", "ref": "cat /tmp/flappy-bird/.git/bp3/runs/*.json | jq -c '{mode,run_id}'", "quote": "{\"mode\":\"host\",\"run_id\":\"20261118T141104Z-node-muse-code-muse-wonder-1.0-c1\"}"}, "verdict": "pass"},
  {"case": "mode derives self", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 config | jq -c '{mode}'", "quote": "{\"mode\":\"self\"}"}, "verdict": "pass"},
  {"case": "no flag surface", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills install --mode host", "quote": "mode is derived from the repo (tracked src/graph + bin/bp3), never passed as a flag: --mode"}, "verdict": "pass"},
  {"case": "skill sets", "rung": 3, "evidence": {"kind": "command", "ref": "./test/mode.sh", "quote": "mode tests: ok (49 assertions)"}, "verdict": "pass"},
  {"case": "mode-aware reads", "rung": 3, "evidence": {"kind": "command", "ref": "grep -n 'desk ? \"./bin/bp3\" : \"bp3\"' skills/bp3g/workflows/node-loop.js", "quote": "skills/bp3g/workflows/node-loop.js:82:  const bp3Bin = desk ? \"./bin/bp3\" : \"bp3\";"}, "verdict": "pass"},
  {"case": "full external conduct", "rung": 3, "evidence": {"kind": "command", "ref": "git -C /tmp/flappy-bird show bp3/graph/flappy-score:docs/graphs/flappy-score/nodes/score-counter/state.yaml; node /tmp/flappy-bird/smoke.mjs", "quote": "state: landed"}, "verdict": "pass"},
  {"case": "mode recorded", "rung": 3, "evidence": {"kind": "command", "ref": "cat /tmp/flappy-bird/.git/bp3/runs/*.json | jq -c '{mode,run_id}'", "quote": "{\"mode\":\"host\",\"run_id\":\"20261118T141104Z-node-muse-code-muse-wonder-1.0-c1\"}"}, "verdict": "pass"},
  {"case": "regression", "rung": 3, "evidence": {"kind": "command", "ref": "make check", "quote": "make-exit:0"}, "verdict": "pass"}
]
```
