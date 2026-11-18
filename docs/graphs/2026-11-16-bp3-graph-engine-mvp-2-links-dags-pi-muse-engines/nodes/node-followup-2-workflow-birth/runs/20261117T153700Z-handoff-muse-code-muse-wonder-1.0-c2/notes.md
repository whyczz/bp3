# followup.2 workflow-birth — author notes (cycle 2)

Task: the one missing row from the 6f124a6 grade — a REAL conduct
(node -> grade -> land) from a foreign-dialect conductor root with
zero read refusals. No other row redone; no product code changed.

Result: PASS. Fixture graph `2026-11-17-followup2-fixture`, node
`exp-fixture-trivial`, reached `landed` (node_fin; rollup graph_fin).
Conduct reads: 6 node reads + 1 rollup read, all `ok:true` via the
desk binary launched from `/Users/whycz/m/bp3`. **Read refusals: 0.**
Control probe (not counted): the root binary answers the same read
with old-dialect usage, exit 2. Full commands/outputs in this run's
tape.log; committed summary in `../conduct-cycle2.md`.

Lessons:
- Birth is a cwd fact, not a code fact: the same read succeeds or
  refuses purely on which `bin/bp3` the cwd resolves. deskNote is
  the whole fix, and it held under a real launch.
- One session claiming sibling edge links makes the session rung
  point at the latest claim (grade cast warned
  W_CONTEXT_ENV_MISMATCH and its ledger line carries the verify
  run-id). Parallel children need separate sessions, or claims must
  interleave claim->cast per edge.
- A fresh desk has no `_build`; conducting from it needs BP3_G_BIN
  pointed at a built main.exe until desks learn to build/share one.
