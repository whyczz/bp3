# Run notes — exp-dogfood-1-link-drive audit (node, cycle 1)

## Lessons

- The drive is the test: `test/dogfood-link.sh` at the bound commit reproduces all four drives, the three claim attacks, the Pi claim tree, and the supervisor fold in a temp repo; re-running it here returned ok.
- Link briefs win on chars from observed briefs (old 425 vs link 68-70 in the handoff run folder), not estimates.
- Wrong-desk refusal is at `bp3 e` context resolution (`E_NO_CONTEXT`), not at claim time.
- Pi death/bubble is not asserted by the dogfood fixture itself; it is covered at the same commit by `test/pi-tree.test.mjs`, which also returned ok.

## Evidence matrix

```json
[
  {"case": "both drives land", "rung": 3, "evidence": {"kind": "command", "ref": "./test/dogfood-link.sh", "quote": "dogfood-link tests: ok"}, "verdict": "pass"},
  {"case": "link brief is one line", "rung": 3, "evidence": {"kind": "command", "ref": "./test/dogfood-link.sh", "quote": "dogfood-link tests: ok"}, "verdict": "pass"},
  {"case": "attacks refuse at claim", "rung": 3, "evidence": {"kind": "command", "ref": "./test/dogfood-link.sh", "quote": "dogfood-link tests: ok"}, "verdict": "pass"},
  {"case": "metrics observed", "rung": 3, "evidence": {"kind": "command", "ref": "./test/dogfood-link.sh", "quote": "dogfood-link tests: ok"}, "verdict": "pass"},
  {"case": "supervised proof unchanged", "rung": 3, "evidence": {"kind": "command", "ref": "./test/dogfood-link.sh", "quote": "dogfood-link tests: ok"}, "verdict": "pass"},
  {"case": "Pi nested tree", "rung": 3, "evidence": {"kind": "command", "ref": "node test/pi-tree.test.mjs", "quote": "pi-tree tests: ok"}, "verdict": "pass"},
  {"case": "env-set run-id (standing ruling)", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_HARNESS=muse-code BP3_MODEL=muse-wonder-1.0 ./bin/bp3 harness link claim bp3link_bffb697c34ef5a30f45d9d9caf483f1c", "quote": "{\"ok\":true,\"run_id\":\"20261117T062205Z-node-muse-code-muse-wonder-1.0-c1\",\"kind\":\"node\",\"graph\":\"2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines\",\"node\":\"exp-dogfood-1-link-drive\",\"edge\":null,\"state\":\"claimed\""}, "verdict": "pass"}
]
```
