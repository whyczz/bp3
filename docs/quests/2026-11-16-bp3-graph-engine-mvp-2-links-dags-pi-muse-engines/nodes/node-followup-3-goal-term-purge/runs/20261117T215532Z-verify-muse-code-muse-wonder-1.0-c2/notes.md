# Verify lessons — node-followup-3-goal-term-purge @ 7382b94 (verify c2)

- Claimed link returned run_id 20261117T215532Z-verify-muse-code-muse-wonder-1.0-c2 as expected; run folder did not pre-exist.
- Fresh rung-2 fails confirm supplied matrix: GRAPH.md has 18 broken `experiments/exp-*/NODE.md` record links (line 685 for this node; target missing, live path is nodes/node-*/NODE.md), so "files renamed" fails. AGENTS.md:19,30 (and naming/using-bp3 skills) still say GOAL.md while the live record is GRAPH.md, so "terms synced" fails.
- Fresh rung-3 passes: scoped grep quest exits 1 (zero) after named exemptions, migrate dry-run is idempotent no-op, conduct read returns handed_off cycle 2 at bound commit.
- One accidental `make check` ran in the conductor checkout (missing workdir arg) and is disregarded; the decisive worktree `make check` is recorded in tape.log separately.
- Verdict is fail on the two gated rung-2 rows regardless of make check outcome; do not edit work as verify child.
- Fresh worktree make check: FAILED at ./test/harness.sh watch drip (make_check_exit:2 in tape); g/ready/skills constituents passed before that failure.
- Verify edge attempted with BP3_RUN_ID stamped, returned E_ILLEGAL_EDGE: state is now todo cycle 3 (parallel grade moved handed_off->todo), legal_edges handoff/block/delete; verify no longer legal. Fresh read confirms todo cycle3 at bound commit.
