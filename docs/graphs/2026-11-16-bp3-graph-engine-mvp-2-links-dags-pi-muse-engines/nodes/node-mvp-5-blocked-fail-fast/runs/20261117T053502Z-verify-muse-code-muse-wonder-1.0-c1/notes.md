# Run notes — exp-mvp-5-blocked-fail-fast (verify, cycle 1)

Verify stance: judge only on fresh output, never claimed green.

Claims checked (fresh, in this run, tee'd to tape.log):
- git status --porcelain — empty stdout, exit 0; HEAD is bound commit 4d00100df1ae03d273af85cb5065f73db0a71d54.
- git show bound commit — present, 7 files, blocked-fail-fast message.
- node test/induct-node.test.mjs — fresh: "induct-node tests: ok", exit 0.
- ./test/blocked.sh — fresh: "blocked tests: ok", exit 0.
- Pi gated rows (tree bubbles to root, whole Pi tree dies, Pi revival is a
  fresh tree, unreaped Pi grandchild, root Pi session dies) — verdict
  missing in matrix; handoff notes state "Pi tree-death process proof
  (real process table, unreaped grandchild) stays with the Pi drive; this
  commit lands the Muse terminal-bubble form". No Pi process proof in
  bound commit diff (grep found none).

Verdict: fail. Per grade rule, any gated row with verdict missing blocks;
the five Pi rows are missing, not deferred. Passing Muse/shell tests do
not substitute for the missing Pi tree-death evidence.

Lesson: a handoff that scopes Pi proof to a later drive still leaves the
exp's Pi acceptance rows gated-missing at verify; deferral must be
recorded as deferred, not left missing, or the grade is negative.
