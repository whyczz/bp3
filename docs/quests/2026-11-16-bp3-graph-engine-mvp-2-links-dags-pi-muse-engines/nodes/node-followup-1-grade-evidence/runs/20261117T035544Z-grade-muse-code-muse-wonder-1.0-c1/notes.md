# Grade notes — exp-followup-1-grade-evidence @ 5cce4cc

Verdict cast: needs_fix (see tape.log for commands run).

Lessons:
- Rungs 1–3 decided this grade; zero whole-tape reads, no rung-5a pointer needed.
- All 8 acceptance rows pass in fixtures (`node test/induct-grade.test.mjs`: ok; conduct tests ok; workflow copies in sync), and rung-2 git/ledger checks corroborate (clean tree, bound commit, handoff line with stamped run_id read from the exp branch).
- The gated matrix row `adherence: run folder present` is `fail` (quote: "no run folder with tape.log and notes.md"). Per the grade contract and the workflow's own `outcomeFor`, any gated fail means the work is not correct, so the negative verdict is cast even though fixture tests are green — adherence fails gate exactly like the dirty-tree fixture (test lines 490–496).
- Direct filesystem listing now shows handoff/node folders complete; the minted fail likely reflects what the validations transport observed at mint time. That discrepancy is for the author cycle to resolve (transport desk/observation vs. pipeline expectation), not for the grade child to override by shipping over a gated fail.
- Rung 4: traverse SKILL text and code comments agree with the implementation; no comment/code mismatch found.
