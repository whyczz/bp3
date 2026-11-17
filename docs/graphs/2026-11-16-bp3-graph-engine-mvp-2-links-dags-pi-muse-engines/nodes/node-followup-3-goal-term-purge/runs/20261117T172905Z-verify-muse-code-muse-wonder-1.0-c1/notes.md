# verify exp-followup-3-goal-term-purge c1 — notes

- Claimed link bp3link_9ed1af111495687d63443ae3a55a13a0, run_id 20261117T172905Z-verify-muse-code-muse-wonder-1.0-c1 as expected. Run folder did not pre-exist.
- Fresh rung2: commit c0ab195fde5e12559ca72c71e1624e0b3c21bbf7 exists; GOAL.md present at that commit, QUEST.md absent; naming SKILL.md at commit says goal/graph as matrix quotes; handoff run folder 20261117T155848Z has tape.log+notes.md; tracked tree clean (only untracked run folders/.bp3-context.json).
- Fresh rung3: `./bin/bp3 quest demo r parser-fix` exits 2 with new usage (no quest door) — skills/code door renamed ok. `bp3 g r` shows exp-followup-3-goal-term-purge handed_off at c0ab195 — conduct survives.
- Decisive fail: `git grep -i -w quest c0ab195 -- docs/goals/` excl runs/ledger/this EXPERIMENT.md returns 670 lines, first `docs/goals/2026-11-05-bp3-mvp/GOAL.md:11: scheduling, and survives the Controller dying mid-flight. When this Quest` — exactly the matrix grep-proof fail quote. Gated fail row blocks pass regardless of other rows.
- Ledger path in matrix (experiments/.../ledger.jsonl) not present on disk; graph read via `bp3 g r` is the authoritative conduct evidence used instead. Not needed to decide: grep fail already decides.
- Verdict: fail, bound to c0ab195, reason grep-proof.
- Fresh make check: make-check-pipe-status:0 (all suites ok, incl pi-tree 13/13). So code-renamed passes; grep-proof is the sole gated fail.
- During make check, node moved handed_off->blocked by a parallel child at 2026-11-17T17:37:56Z with same grep reason (671 hits). Verify edge attempt follows anyway per instructions; if refused, that refusal is recorded in tape.
