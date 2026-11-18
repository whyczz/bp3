# Verify notes — exp-dogfood-1-link-drive, cycle 1 (verify)

- Bound commit adfd7b0ff6671735a1260c3c9f4c6bc48a57dc53 == HEAD; diff is only Makefile + test/dogfood-link.sh; tree clean (git status --porcelain empty, runs/ gitignored).
- Fresh exp checks at bound commit: ./test/dogfood-link.sh -> "dogfood-link tests: ok"; node test/pi-tree.test.mjs -> "pi-tree tests: ok". Both also passed inside make check.
- Handoff artifacts corroborate: link briefs 1 line (68-70 chars) vs old 425; attacks.log shows E_LINK_SPENT / E_NOT_FOUND / E_NO_CONTEXT; metrics.json records 4 drives + 3 attacks refused.
- Full `make check` ran fresh and passed skills/q/ready/diagram/blocked/pi-tree/harness/config/link/dogfood-link/context/pi-extension, then failed once at unrelated test/worktree.sh (E_WORKTREE git worktree add) while sibling children shared this worktree; ./test/worktree.sh standalone immediately after -> "worktree tests: ok" (exit 0). Treated as concurrency flake, not a bound-commit defect; no gated matrix row covers worktree.sh.
- Lesson: in parallel-child swarms sharing one worktree, fixed-path git-worktree fixtures collide; grade on the exp's own checks and re-probe the flaked unrelated test standalone before letting it veto.
