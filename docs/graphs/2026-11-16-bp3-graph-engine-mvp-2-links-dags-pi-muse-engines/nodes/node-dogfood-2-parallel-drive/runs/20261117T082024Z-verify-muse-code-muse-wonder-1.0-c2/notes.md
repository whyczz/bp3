# exp-dogfood-2-parallel-drive — verify run notes (cycle 2)

- Claimed link returned run_id `20261117T082024Z-verify-muse-code-muse-wonder-1.0-c2`, as expected. Run folder was absent; created fresh.
- Rung 1: EXPERIMENT.md asks for true parallelism, isolation, serial land, honest scorecard, unchanged quality floor, Pi tree death+revival, Muse parity bubble, env-set run-id.
- Rung 2: `git status --porcelain` empty, HEAD and bound commit both `7a0dfca3d413f17647d6beb63ad267d25ff881ac`; commit changes only `test/dogfood-parallel.sh` (+210).
- Rung 3 fresh, not claimed: `bash test/dogfood-parallel.sh` exit 0 — `ready_wall_ms 4011 < serial_sum_ms 7022, wall_saved_ms 3011, tokens null`; bubble scorecard `pi_bubble blocked, pi_fresh_run 20261117T082110Z-node-pi-test-model-c1, claude_bubble blocked, claude_fresh landed, sibling_pi handed_off, sibling_claude landed`.
- Lesson: concurrent `make check` runs in one worktree (sibling grade child plus an overlapping rerun) interfered and produced truncated/flaky failures. A clean solo `make check` after the sibling finished passed: `MAKE_EXIT:0`, ending `install tests: ok` (see `make-check.log` in this run folder and tape.log).
- No whole-tape (rung 5b) read was needed; grade decided at rungs 1-3. No work files edited.
- Verdict: pass.
