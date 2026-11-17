# Verify notes — exp-mvp-3-ready-set-timing cycle 2

- Fresh evidence only: ran ./test/ready.sh and node test/induct-node.test.mjs in this session; both printed ok, exit 0.
- Bound-commit check: exported 105cbea to /tmp and reran; ready.sh needed _build artifacts copied in, then also "ready tests: ok". Test/implementation files are unchanged between 105cbea and HEAD (later commits touch only followup.1 grade files).
- git status --porcelain empty before and after runs; timing line quotable: "timing read clean: tip unchanged, worktree entries: 0".
- Lesson: git-archive exports omit _build, so a bare export fails for missing main.exe — copy the build tree or run in the worktree.
