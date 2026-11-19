# followup.6 check-tiers — verify run notes (cycle 1)

Verify stance: judged only on fresh output in this session, not claimed green.

- Bound commit 0f60c7a50a826ca932a99c0097a2baf7ac227877 at HEAD; no tracked modifications (one untracked sibling run folder under runs/ only).
- Fast tier: `time make check-fast` exit 0, 53.795s (<120s), suites: lint check-skills skills build pi-tree bp3-pi bp3g check-tiers; no harness.sh.
- Full tier: check recipe byte-identical before/after (diff only .PHONY + added check-fast/check-changed block, 44a45,53); `time make check` exit 0 (full-exit:0), 6m40.816s.
- Selector fresh: skills->check-skills/skills/bp3g; src->build/g; renders->skills-check/wf:bp3g-grade; unknown/docs->fast tier non-empty.
- Retired sweep: ok in 0.081s; planted QUEST.md probe failed naming skills/demo/SKILL.md:1; test/check-tiers.sh ok (14 assertions) covers planted line-5, fossil, and fail-before-suite.
- Cycle text in skills/bp3g/SKILL.md:207-211 names per-cycle check-changed/check-fast, full only at grade/land.
- No deleted files in f96a969^..HEAD.

Lesson: `--list` with no paths reads git changed paths, so in a dirty worktree it prints the fast list rather than the stderr fail-safe line; the empty-tree fail-safe is covered by script code and check-tiers unknown-path fixture.
