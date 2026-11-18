# Audit notes — exp-mvp-5-blocked-fail-fast @ 4d00100

Run: 20261117T053338Z-node-muse-code-muse-wonder-1.0-c1
Bound commit: 4d00100df1ae03d273af85cb5065f73db0a71d54 (HEAD verified)

## Lessons

- Muse fail-fast is landed: typed failure classifies, blocks once verbatim, orphans replace without blocking, bubble carries facts only; shell fixture carries the bp3 state contract. Both suites pass live.
- Pi process-tree proof is absent from this commit by the author's own note; the five Pi-specific acceptance cases have no Pi process-table, pid, or session artifact and are graded missing, not deferred — EXPERIMENT.md names no owning exp for them.
- Conductor/root revival rests on the node read's blocked:{reason,checkpoint,since} field; that is tested at the state layer, distinct from the unproven Pi root-death process case.
- No rung-5 tape read was needed: every row decided at rungs 2-3.

## Matrix

```json
[
  {"case": "edge completes", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "Pi tree bubbles to root", "rung": 3, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-5-blocked-fail-fast/runs/20261117T045107Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Pi tree-death process proof (real process table,\n  unreaped grandchild) stays with the Pi drive; this\n  commit lands the Muse terminal-bubble form of the\n  same law."}, "verdict": "missing"},
  {"case": "whole Pi tree dies", "rung": 3, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-5-blocked-fail-fast/runs/20261117T045107Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Pi tree-death process proof (real process table,\n  unreaped grandchild) stays with the Pi drive; this\n  commit lands the Muse terminal-bubble form of the\n  same law."}, "verdict": "missing"},
  {"case": "Pi revival is a fresh tree", "rung": 3, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-5-blocked-fail-fast/runs/20261117T045107Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Pi tree-death process proof (real process table,\n  unreaped grandchild) stays with the Pi drive; this\n  commit lands the Muse terminal-bubble form of the\n  same law."}, "verdict": "missing"},
  {"case": "unreaped Pi grandchild", "rung": 3, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-5-blocked-fail-fast/runs/20261117T045107Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Pi tree-death process proof (real process table,\n  unreaped grandchild) stays with the Pi drive; this\n  commit lands the Muse terminal-bubble form of the\n  same law."}, "verdict": "missing"},
  {"case": "root Pi session dies", "rung": 3, "evidence": {"kind": "file", "ref": "docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-5-blocked-fail-fast/runs/20261117T045107Z-handoff-muse-code-muse-wonder-1.0-c1/notes.md", "quote": "Pi tree-death process proof (real process table,\n  unreaped grandchild) stays with the Pi drive; this\n  commit lands the Muse terminal-bubble form of the\n  same law."}, "verdict": "missing"},
  {"case": "edge returns typed failure", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "`needs_fix` below cycle cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "cycle cap exceeded", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "human decision required", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "human answers", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "stale worker returns after block", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "edge worker dies silently", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-node.test.mjs", "quote": "induct-node tests: ok"}, "verdict": "pass"},
  {"case": "sibling nodes are ready", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"},
  {"case": "conductor restarts", "rung": 3, "evidence": {"kind": "command", "ref": "./test/blocked.sh", "quote": "blocked tests: ok"}, "verdict": "pass"}
]
```
