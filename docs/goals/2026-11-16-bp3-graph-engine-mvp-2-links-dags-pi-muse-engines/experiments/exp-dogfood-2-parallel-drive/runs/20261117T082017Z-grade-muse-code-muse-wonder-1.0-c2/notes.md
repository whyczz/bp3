# Grade notes — exp-dogfood-2-parallel-drive cycle 2

- Bound commit 7a0dfca is test-only: +210 lines in test/dogfood-parallel.sh adding the Pi/Muse bubble drive. Header comments agree with the code (Pi: real processes, one facts-only bubble, process-table death, fresh tree; Muse: real induct-node workflow, one block, fresh disjoint run-ids, sibling unaffected).
- Verified by running, not reading: `bash test/dogfood-parallel.sh` → ok (scorecard ready_wall 3957ms < serial 6920ms; bubble scorecard pi/claude blocked, claude_fresh landed, siblings unaffected). `make check` → MAKE_EXIT:0 on re-run.
- Flake note: first `make check` run failed at pi-tree.test.mjs "watch dispositions grandchild orphaned" (E_NOT_FOUND); the same test passed twice standalone and the full suite then passed. Timing race under load, not caused by this diff (file untouched by the commit). Watch if it recurs.
- Clean tree after all runs (git status --porcelain empty); no hand-edited state.
