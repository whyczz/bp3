# verify notes — exp-mvp-2-context-resolution c1

- Bound commit 63d49cd is HEAD; `git show --stat` = feat(mvp.2) 10 files, test/context.sh +113.
- Fresh gate: `make check` exit 0 (tape.log). Includes shellcheck, skills ok, q/harness/config/link/context ok, pi tests 13 pass, worktree/tape/hooks/traverse/completion/release/install ok. Judged on this fresh output only, not handoff claim.
- Live door check: `BP3_RUN_ID=<run_id> ./bin/bp3 e` resolved source=session, state=handed_off, legal_edges includes verify, run_id stamped — matches claimed-session / bare-e cases.
- Context cases (unclaimed W_CONTEXT_UNCLAIMED, env mismatch claim wins, desk rung, ambiguous desk E_NO_CONTEXT with 2 live ids, no false claim) are exercised by test/context.sh inside make check; all passed.
- Working tree shows 3 dirty .agents/workflows/*.js files not in bound commit and not gated by make check lint (which checks skills/traverse/workflows); did not affect gate. Not edited.
- Lesson: verify from make check + one live `bp3 e` probe; desk/session precedence is fully covered by context.sh fixtures, no need for whole-tape rung.
