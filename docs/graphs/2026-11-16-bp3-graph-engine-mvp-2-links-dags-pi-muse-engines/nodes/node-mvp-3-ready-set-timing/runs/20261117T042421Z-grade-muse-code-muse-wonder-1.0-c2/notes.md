# grade notes — exp-mvp-3-ready-set-timing c2

- Code review (code-reviewer): full diff b765d07 + 105cbea read; deps/cycle in main.ml/store.ml (write-time E_DEP_CYCLE naming cycle, E_NOT_FOUND, E_DEPENDENCY handoff gate), BFS waves/ready/starved + ledger-derived timing in store.ml, setup W_SETUP_SLOW local-only in render.ml, induct-node single terminal outcome. Comments agree with code; generated induct-node copies identical; naming reuses settled dep/ready/starved/wall_s/wait_s/dwell_s. No critical/major defect.
- Rung 3 observed: ./test/ready.sh -> "timing read clean: tip unchanged, worktree entries: 0", "ready tests: ok"; node --test test/induct-node.test.mjs -> "induct-node tests: ok"; make lint exit 0. Cycle-2 change is test-only quotable evidence; behavior unchanged, any dirt still fails.
- All gated matrix rows pass with typed evidence; dep-freeze proposal recorded in handoff notes (mutable while todo, reason must name schedule change after todo; no hard freeze yet). No open design question blocks.
- Lesson: keep grade evidence quotable — count and echo the property instead of asserting on silent empty output.
