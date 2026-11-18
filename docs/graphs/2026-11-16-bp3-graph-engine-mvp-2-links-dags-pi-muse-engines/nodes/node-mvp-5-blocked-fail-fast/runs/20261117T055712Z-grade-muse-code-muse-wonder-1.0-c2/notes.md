# Grade notes — exp-mvp-5 cycle 2

- Rung 1: EXPERIMENT.md cycle-2 fix requires real Pi root->node->edge process proof for five Pi rows; no re-deferral.
- Rung 2: bound commit f5b434d adds only test/pi-tree.test.mjs (217 lines) + Makefile wiring (make check, node --check). Clean tree, HEAD matches bound commit.
- Rung 3 (run, not read): induct-node ok, blocked.sh ok, pi-tree ok on rerun. One transient pi-tree flake on first run (watch E_NOT_FOUND before tape bind visible), passed on immediate rerun; recorded, not hidden.
- Rung 4 (code-reviewer): header comment matches cases; death checked via kill(pid,0) process table, facts-only bubble asserted (!("pid" in b)), parent_run_id chain asserted. No lying comments, no hand-edited generated files. Severity: minor — pi-tree watch step is timing-sensitive; fix shape is a bounded retry/wait for tape visibility if flake recurs. Does not block ship.
- Verdict: ship — all gated rows have observed passing evidence; no whole-tape (rung 5) read needed.
