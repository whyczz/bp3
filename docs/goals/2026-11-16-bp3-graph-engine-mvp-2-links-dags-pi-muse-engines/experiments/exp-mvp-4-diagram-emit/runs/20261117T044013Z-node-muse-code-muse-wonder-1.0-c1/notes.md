# Audit notes — exp-mvp-4-diagram-emit @ fe6efe79513040a1ad8b7a8d7e2d275f961d7415

Run: 20261117T044013Z-node-muse-code-muse-wonder-1.0-c1 (claim ok, rung 1-3 only; zero whole-tape reads, no rung 5).

Lessons:
- The fixture test (test/diagram.sh) is the deciding evidence: it builds a diamond graph through bp3 itself, lands one node, blocks another, and diffs before/after — live-graph runs alone cannot show starvation or state movement without mutating state, which an audit must not do.
- Live corroboration matched: both formats on the real quest show identical node labels (state, cycle, exp_fin on landed), the wave-1 grouping, and generated-at timestamps one second apart; deps/starved are `(none)` live because no live node is blocked and rollup deps are empty.
- Derivation log at <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl does not exist for this run; claim verdict itself (run_id, session_id, claimed_at) is the binding evidence. Not gating.
- Makefile wires test/diagram.sh into `check` and shellcheck passes on it; diagram is read-only (fixture asserts branch tip unchanged).

## Evidence matrix

```json
[
  {"case": "ascii current", "rung": 3, "evidence": {"kind": "command", "ref": "./test/diagram.sh", "quote": "diagram tests: ok"}, "verdict": "pass"},
  {"case": "mermaid equivalent", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 q 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines diagram --format mermaid", "quote": "  exp_mvp_4_diagram_emit[\"exp-mvp-4-diagram-emit (handed_off, cycle 1)\"]"}, "verdict": "pass"},
  {"case": "ready-set waves + starvation", "rung": 3, "evidence": {"kind": "command", "ref": "./test/diagram.sh", "quote": "diagram tests: ok"}, "verdict": "pass"},
  {"case": "honest labels", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 q 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines diagram --format ascii", "quote": "quest 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines diagram (generated from live state at 2026-11-17T04:40:48Z)"}, "verdict": "pass"}
]
```
