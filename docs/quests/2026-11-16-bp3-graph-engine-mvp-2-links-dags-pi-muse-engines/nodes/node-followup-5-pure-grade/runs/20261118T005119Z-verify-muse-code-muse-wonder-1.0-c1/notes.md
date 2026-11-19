# followup.5 pure-grade — verify run notes

Run: 20261118T005119Z-verify-muse-code-muse-wonder-1.0-c1
Commit: 4ab3228527b6f0175bfca3b8f4a78184f01debe5

## Fresh evidence (verify stance: run, not read)
- git status --porcelain: no tracked modifications; only untracked
  harness run folders. HEAD == bound commit. Rung-2 adherence holds
  in substance despite the matrix's strict ?? reading.
- node test/bp3g-grade.test.mjs: ok (exit 0)
- node test/bp3g-node.test.mjs: ok (exit 0)
- ./test/g.sh: ok (exit 0)
- make check: FAIL — test/dogfood-parallel.sh bubble drive:
  TypeError: Cannot read properties of null (reading '1')
  at bubble-drive.mjs:161 (harness link claim token parse),
  via skills/bp3g/workflows/bp3g-node.js callApply.
  MAKE_CHECK_EXIT nonzero, make: *** [check] Error 1.
- ./test/dogfood-parallel.sh solo re-run: FAIL, exit 1,
  identical bubble-drive error. Deterministic, not load flake.

## Verdict
fail — regression row: `make check` is not green at the bound
commit. All pure-grade acceptance suites pass, but the full
project gate the node claims green is red.

## Lessons
- Author-claimed "make check green" did not survive a fresh run;
  the bubble fixture's claim-token regex meets the new looper
  apply step in bp3g-node and gets null.
- Untracked run folders in git status are harness artifacts,
  not hand-edited state; grading them as dirt fails every run.
