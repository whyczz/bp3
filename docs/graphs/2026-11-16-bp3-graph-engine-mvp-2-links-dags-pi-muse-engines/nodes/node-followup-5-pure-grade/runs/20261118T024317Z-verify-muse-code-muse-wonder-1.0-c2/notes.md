# verify notes — node-followup-5-pure-grade cycle 2

- Bound commit 31b7c740a485bd43d10edfec07e226f74df3c518 checked fresh in detached worktree /tmp/bp3-grade-31b-verify (rung 3, run not read).
- Fresh: node test/bp3g-grade.test.mjs -> bp3g-grade tests: ok (exit 0); node test/bp3g-node.test.mjs -> bp3g-node tests: ok (exit 0).
- Fresh FAIL: ./test/completion.sh exit 1 — FAIL: flag --mechanical in main.ml not in completions/_bp3. Matches NODE.md correction: flags parsed since 4ab3228 missing from completions at the bound commit; fix exists only in follow-up 0ee41e2 (HEAD), not in 31b7c74.
- Verdict fail on gated regression row (make check green required). Fix: add --verify-verdict/--mechanical to completions/_bp3 and completions/bp3.bash (already in 0ee41e2) and re-grade at that commit.
- Lesson: a handoff RESOLVED claim of make check green must be re-run at the exact bound commit; later-branch fixes do not retro-pass the bound grade.
