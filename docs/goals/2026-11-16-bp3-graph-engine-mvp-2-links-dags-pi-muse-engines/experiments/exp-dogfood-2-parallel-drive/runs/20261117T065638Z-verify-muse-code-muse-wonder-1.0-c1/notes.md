# Verify notes — exp-dogfood-2-parallel-drive c1

Bound commit 51406951173971043235443104c703e78a9eda2c at HEAD; worktree clean.

Fresh checks (this session, tee'd to tape.log):
- `git status --porcelain` — empty, exit 0. Pass.
- `bash test/dogfood-parallel.sh` — exit 0, "dogfood-parallel tests: ok"; scorecard ready_wall_ms 3919 < serial_sum_ms 6872, tokens null with honest note. Parallelism, isolation, serial land, scorecard, env run-id rows pass at rung 3.
- `grep -n "Pi|bubble" test/dogfood-parallel.sh` — no matches, exit 1. The EXPERIMENT.md acceptance rows "Pi tree death + revival" and "Muse parity bubble" have no coverage in the bound commit and are not marked deferred to another exp. Both gated rows are missing.

Lesson: a passing parallel-drive test does not cover the bubble/revival acceptance; missing gated rows fail the grade even when rung-3 drive checks are green. Grade decided at rungs 1-3; no whole-tape (rung 5) read was needed.
