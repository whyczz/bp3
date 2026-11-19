# Audit notes — exp-dogfood-2-parallel-drive @ 7a0dfca

## Lessons
- Cycle-2 bubble proof rides inside test/dogfood-parallel.sh: Pi spawns real
  node/edge processes claiming real links; Muse runs the real induct-node
  workflow against real bp3. Sibling-unaffected is asserted by state, not inference.
- Scorecard honesty: ready_wall_ms 3956 < serial_sum_ms 6882, wall_saved_ms 2926;
  tokens:null with an explicit note rather than invented numbers.
- Full grade decided at rungs 1-3 (records, bound diff, tests run); no tape read needed.

## Matrix
```json
[
  {"case": "true parallelism", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh", "quote": "dogfood-parallel tests: ok"}, "verdict": "pass"},
  {"case": "isolation", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh (desk bleed + per-branch variant asserts)", "quote": "dogfood-parallel tests: ok"}, "verdict": "pass"},
  {"case": "serial land", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh (land 1, land 2, merge-base ancestor checks)", "quote": "dogfood-parallel tests: ok"}, "verdict": "pass"},
  {"case": "scorecard honest", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh scorecard output", "quote": "\"ready_wall_ms\": 3956, \"serial_sum_ms\": 6882, \"wall_saved_ms\": 2926, \"tokens\": null"}, "verdict": "pass"},
  {"case": "quality floor unchanged", "rung": 3, "evidence": {"kind": "command", "ref": "make check", "quote": "MAKE_EXIT:0"}, "verdict": "pass"},
  {"case": "Pi tree death + revival", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh bubble drive", "quote": "{\"pi_bubble\":\"blocked\",\"pi_fresh_run\":\"20261117T081042Z-node-pi-test-model-c1\",\"claude_bubble\":\"blocked\",\"claude_fresh\":\"landed\",\"sibling_pi\":\"handed_off\",\"sibling_claude\":\"landed\"}"}, "verdict": "pass"},
  {"case": "Muse parity bubble", "rung": 3, "evidence": {"kind": "command", "ref": "bash test/dogfood-parallel.sh bubble drive", "quote": "{\"pi_bubble\":\"blocked\",\"claude_bubble\":\"blocked\",\"claude_fresh\":\"landed\",\"sibling_claude\":\"landed\"}"}, "verdict": "pass"},
  {"case": "env-set run-id (standing ruling)", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_HARNESS=muse-code BP3_MODEL=muse-wonder-1.0 ./bin/bp3 harness link claim bp3link_694cc6a5862747215341dece9686f866", "quote": "{\"ok\":true,\"run_id\":\"20261117T080958Z-node-muse-code-muse-wonder-1.0-c2\",\"kind\":\"node\",\"node\":\"exp-dogfood-2-parallel-drive\",\"state\":\"claimed\"}"}, "verdict": "pass"}
]
```
