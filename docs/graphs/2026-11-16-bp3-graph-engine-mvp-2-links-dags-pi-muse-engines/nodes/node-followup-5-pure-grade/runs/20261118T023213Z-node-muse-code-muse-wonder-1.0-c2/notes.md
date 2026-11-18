# followup.5 pure-grade — audit (node) run notes

Run: 20261118T023213Z-node-muse-code-muse-wonder-1.0-c2
Bound commit: 31b7c740a485bd43d10edfec07e226f74df3c518
Harness: muse-code / muse-wonder-1.0 (link claim returned the expected run_id)

## Lessons
- Bound-commit grading matters: HEAD (0ee41e2) already carries the
  completion-flags follow-up, so `make check` green at HEAD does not
  acquit 31b7c74; at the bound commit `./test/completion.sh` fails on
  `--mechanical` missing from `completions/_bp3` while the parser in
  `src/graph/main.ml` already accepts `--verify-verdict`/`--mechanical`.
- The cycle-2 RESOLVED note at the bound commit claimed `make check`
  exit 0 before the gate finished; the correction lives only in the
  follow-up commit, so the bound commit's own claim is not evidence.
- Prior typed evidence for `test/dogfood-parallel.sh` was reused
  verbatim with its source and the suite was not re-executed; all
  other rows were decided by fresh rung-3 runs at the bound commit
  (`node test/bp3g-grade.test.mjs`, `node test/bp3g-node.test.mjs`,
  `./test/completion.sh` in a detached worktree of 31b7c74).
- `./test/g.sh` did not finish within 180s in this sandbox (timeout
  124, no failure line); mechanical/single-cast engine behavior is
  therefore graded on the `bp3g-grade` workflow fixtures that did
  run, not on an unobserved `g.sh` pass.

## Evidence matrix (verbatim JSON)

[
  {"case": "pure audit", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "single cast", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "safe replay", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: superseded", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: empty fix", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "pushback: blocked", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "fix ledger live", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-node.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-node tests: ok"}, "verdict": "pass"},
  {"case": "regression", "rung": 3, "evidence": {"kind": "command", "ref": "./test/completion.sh at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "FAIL: flag --mechanical in main.ml not in /tmp/bp3-grade-31b/completions/_bp3"}, "verdict": "fail"},
  {"case": "audit reuse: prior evidence not re-executed", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "audit reuse: no prior evidence executed", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "audit reuse: quoted with source", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: never blocks at cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: disagreement blocks at cap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "mechanical: live cycle zero owner contact", "rung": 3, "evidence": {"kind": "command", "ref": "node test/bp3g-grade.test.mjs at 31b7c74 (detached worktree /tmp/bp3-grade-31b)", "quote": "bp3g-grade tests: ok"}, "verdict": "pass"},
  {"case": "test/dogfood-parallel.sh", "rung": 3, "reused_from": "docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-5-pure-grade/runs/20261118T013353Z-handoff-muse-code-muse-wonder-1.0-c2/notes.md", "evidence": {"kind": "command", "ref": "docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-5-pure-grade/runs/20261118T013353Z-handoff-muse-code-muse-wonder-1.0-c2/notes.md", "quote": "After the fix: ./test/dogfood-parallel.sh exit 0 (\"dogfood-parallel tests: ok\"; bubble scorecard pi/claude blocked, claude fresh landed, siblings unaffected)."}, "verdict": "pass"}
]
