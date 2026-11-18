# followup.5 pure-grade — audit (node) run notes

Run: 20261118T033752Z-node-muse-code-muse-wonder-1.0-c3
Bound commit: 84be74a6ee6a97288269e37732a952820d982853
Harness: muse-code / muse-wonder-1.0 (link claim returned the expected run_id)

## Lessons
- At the bound commit the completion-flags fix rides by ancestry (0ee41e2): ./test/completion.sh passes fresh, unlike at 31b7c74 where it failed on --mechanical.
- Workflow fixtures are the decidable rung-3 evidence: node test/bp3g-grade.test.mjs and ./test/bp3g.sh cover pure audit, single cast, replay, all three pushbacks, audit reuse, and mechanical/disagreement in one green run.
- Full make check did not finish in this sandbox: it terminated at ./test/g.sh (timeout 124, also in the prior cycle audit); no make-check-green claim is made from an unobserved finish, so the regression row is missing, not pass.
- Fix ledger in NODE.md shows live OPEN→RESOLVED cycles (cycle 2 dogfood-parallel, cycle 3 completion flags) with the author RESOLVED entry in its fix commit.

## Evidence matrix (verbatim JSON)

[
  {"case": "pure audit", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "single cast", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "safe replay", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: superseded", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: empty fix", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: blocked", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "fix ledger live", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-node.test.mjs at 84be74a", "quote": "bp3g-node tests: ok"}, "verdict": "pass"},
  {"case": "regression", "rung": 3, "evidence": {"kind": "command", "ref": "make check at 84be74a (timeout 240s)", "quote": "make: *** [check] Terminated: 15"}, "verdict": "missing"},
  {"case": "audit reuse: prior evidence not re-executed", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "audit reuse: no prior evidence executed", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "audit reuse: quoted with source", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: never blocks at cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: disagreement blocks at cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: live cycle zero owner contact", "rung": 3, "evidence": {"kind": "command", "ref": "./test/bp3g.sh at 84be74a", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"}
]
