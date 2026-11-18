# followup.5 pure-grade — grade run notes (cycle 1)

Run: 20261118T005112Z-grade-muse-code-muse-wonder-1.0-c1
Bound commit: 4ab3228527b6f0175bfca3b8f4a78184f01debe5
Verdict: needs_fix (regression row)

## What I ran (rung 3, executed — not read about)
- `node test/bp3g-grade.test.mjs`: ok. `node test/bp3g-node.test.mjs`: ok.
  `./test/g.sh`: ok. All at the bound commit in this worktree.
- `make check` run 1: failed at test/pi-tree.test.mjs (watch/orphan
  E_NOT_FOUND on a fresh test run-id). Re-run alone: ok — load flake.
- `make check` run 2: got past pi-tree, failed at test/dogfood-parallel.sh
  "bubble drive": TypeError `Cannot read properties of null (reading '1')`
  at bubble-drive.mjs:161, via bp3g-node.js:488 callApply.
- Reproduced standalone 3x at bound commit; then proved causality:
  dogfood-parallel PASSES on parent b1c142d and FAILS in a pristine
  worktree of 4ab3228 (built fresh). The bound commit regressed it.

## Why it regressed
- The new looper apply child (bp3g-node.js callApply, label "apply
  <node>", input "Run exactly `./bin/bp3 g ... grade --verify-verdict
  ...`") is not handled by bubble-drive's agent() mock, which parses a
  bp3link_ token from spawn text and dereferences the null match.
- dogfood-parallel.sh's ledger jq also still demands a separate
  `verify / pass` ledger line; the combined cast writes one grade line
  carrying verify_verdict. The author fixed this mock pattern in
  test/bp3g-node.test.mjs (their own lesson) but missed this suite.

## Matrix rows re-checked
- Adherence "no hand-edited state" / "clean commit" (matrix: fail) —
  not sustained: zero modified/staged tracked files; only untracked
  run-evidence dirs; SKILL.md mirrors differ from source only by the
  GENERATED header; workflow mirrors byte-identical. I pass both.
- All acceptance fixtures pass; engine fold (store.ml) mirrors main.ml
  for ship+verify pass/fail; mechanical never blocks; pushbacks named
  and pre-cast (casts:0). But regression row fails on executed evidence.

## Lessons
- A workflow-shape change must be swept against every mock that
  dispatches on spawn text, not only the suite the author edited.
- "make check green" in handoff notes is a claim; the grade re-runs
  the gate and bisects to the parent before believing a failure.
- Pure grade held: zero `bp3 g u` calls from this run; verdict is data.
