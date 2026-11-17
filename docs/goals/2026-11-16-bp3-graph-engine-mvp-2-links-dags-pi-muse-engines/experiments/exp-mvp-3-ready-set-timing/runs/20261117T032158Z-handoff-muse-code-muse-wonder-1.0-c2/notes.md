# exp-mvp-3-ready-set-timing — author run notes, cycle 2

- Cycle 1 (commit b765d076) already shipped the exp: node deps
  (`--depends-on`, `dep` verb, `E_DEP_CYCLE`/`E_NOT_FOUND` at write
  time, `E_DEPENDENCY` handoff gate), BFS `ready_set_waves`/`ready`,
  `starved` blast radius, ledger-derived `wall_s`/`wait_s`/`dwell_s`,
  per-Run `setup_wall_s` with local `W_SETUP_SLOW` (default 180s),
  serial land, and the `induct-node` loop. Naming reuses the settled
  words (`dep`, `ready`, `starved`, `wall_s`/`wait_s`/`dwell_s`).
- Cycle-2 defect was grader paperwork, not product: the gated row
  `adherence: no hand-edited state` carried an empty quote
  (`git status --porcelain` on a clean tree), which the grade's
  `typedEvidence` (kind + non-empty ref + non-empty quote) normalizes
  to `missing`, so a green product blocked and paged the human.
  The generic fix (audit re-collects untyped rows) is followup.1's;
  this cycle supplies the typed evidence at its root here.
- Fix (this commit 105cbea): `test/ready.sh` no longer proves
  "reads write nothing" with a silent empty-string check. It counts
  worktree entries and tracked ledger/state files and echoes both
  counts, so the property has a quotable line. Behavior is unchanged:
  any dirt still fails the test. No src change was needed; the
  cycle-1 timing/setup assertions already forbade ledger leaks.
- Dep-freeze exploration stands from cycle 1: deps stay
  mutable-but-logged (state+cycle on the `dep` line); keep deps
  mutable while `todo`, require the reason to name the schedule
  change after `todo`; no hard freeze justified yet.

Typed evidence for the previously missing gated row:

```json
[
  {"case": "adherence: no hand-edited state", "rung": 2, "evidence": {"kind": "command", "ref": "git show --name-only --format= HEAD (105cbea174e8b204413cf2428aea78eec2e344d0)", "quote": "test/ready.sh"}, "verdict": "pass"},
  {"case": "adherence: no hand-edited state (cycle-1 code)", "rung": 2, "evidence": {"kind": "command", "ref": "git show --name-only --format= b765d076ad5aca6b322a95f193c15ae190825a9c", "quote": ".agents/workflows/induct-node.js, Makefile, bin/bp3, skills/traverse/SKILL.md, skills/traverse/workflows/induct-node.js, src/quest/main.ml, src/quest/render.ml, src/quest/store.ml, test/induct-node.test.mjs, test/ready.sh, test/skills.sh, test/traverse.sh (12 files, 0 ledger/state paths)"}, "verdict": "pass"},
  {"case": "timing derived / reads write nothing", "rung": 3, "evidence": {"kind": "command", "ref": "./test/ready.sh", "quote": "timing read clean: tip unchanged, worktree entries: 0; tracked ledger/state files on fixture tip: 0; ready tests: ok"}, "verdict": "pass"}
]
```

- Verification: `./test/ready.sh` -> `ready tests: ok` (with the two
  new count lines); `node --test test/induct-node.test.mjs` ->
  `induct-node tests: ok`; `make lint` + skills/q/config/link/
  context/traverse/completion all ok in this run. Full `make check`
  was attempted twice and timed out inside the long harness/pi
  suites (unrelated to this test-only change; cycle 1 ran the full
  gate green on the same src) — stated, not claimed.
