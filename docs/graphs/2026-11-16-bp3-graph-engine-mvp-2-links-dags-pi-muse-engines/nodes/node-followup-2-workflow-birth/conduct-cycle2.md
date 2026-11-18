# Cycle 2 real conduct — foreign-dialect conductor root (exp-followup-2-workflow-birth)

One REAL conduct (no mock host): fixture graph `2026-11-17-followup2-fixture`,
node `exp-fixture-trivial`, driven node-loop -> bp3g-grade -> bp3g-land in
sequence. Every read/write ran the desk binary; every conduct read was
launched from the conductor root `/Users/whycz/m/bp3` (whose `bin/bp3`
speaks the old `bp3 q|graph` dialect) and cd'd to the fixture desk first,
exactly as the workflows' deskNote prompts require.

- Fixture desk: `.bp3/worktrees/2026-11-17-followup2-fixture` under the
  graph worktree (via `bp3 harness desk prepare --graph`), renders fresh
  (`bp3 skills check` ok for node-loop, bp3g-grade, bp3g-land, bp3g-node).
- Fixture bound commit: `fafcc145933c37a38fac5125539f6cb06ca5c59e`
  (EXPERIMENT.md + fixture-proof.txt, committed in the fixture desk).
- Runs: handoff `20261117T154046Z-handoff-muse-code-muse-wonder-1.0-c1`,
  audit `20261117T154229Z-node-muse-code-muse-wonder-1.0-c1`,
  grade `20261117T154229Z-grade-muse-code-muse-wonder-1.0-c1`,
  verify `20261117T154229Z-verify-muse-code-muse-wonder-1.0-c1`,
  land `20261117T154258Z-land-muse-code-muse-wonder-1.0-c1`.
  find-tape resolved the handoff Run's claimed session and bind-tape bound it.

## Read ledger (all `bp3 g <fixture> r exp-fixture-trivial`, desk binary)

| # | Step | State returned | ok |
|---|---|---|---|
| 1 | node-loop before | todo | true |
| 2 | node-loop re-read | handed_off | true |
| 3 | grade before | handed_off (commit bound) | true |
| 4 | grade re-read | approved | true |
| 5 | land before | approved | true |
| 6 | land re-read | landed, fin node_fin | true |

Plus the rollup read `bp3 g r <fixture>`: rollup landed, fin goal_fin.

**Read refusals: 0 of 6 node reads (0 of 7 including the rollup read). PASS.**

Control (not counted): `(cd /Users/whycz/m/bp3 && ./bin/bp3 g <fixture> r
exp-fixture-trivial)` printed the old-dialect usage line and exited 2 —
the foreign root binary cannot speak the desk dialect at all, which is
the hazard the deskNote reads defend against.

Full verbatim commands and outputs: this run's `tape.log` (run folder
`20261117T153700Z-handoff-muse-code-muse-wonder-1.0-c2`); fixture ledger
on `bp3/exp/2026-11-17-followup2-fixture/exp-fixture-trivial`.

## Honest caveats

- One session played conductor and every edge child sequentially (no
  parallel grade/verify spawns). The grade ledger line is stamped with
  the verify run-id: both links were claimed in one session before the
  casts, so the session rung resolved to the latest claim and the grade
  cast carried `W_CONTEXT_ENV_MISMATCH`. Verdicts, bound commit, and
  state sequence are exact; no read was refused.
- Desk invocations set `BP3_G_BIN` to the graph worktree's built
  `main.exe` because a fresh desk has no `_build`; same binary/source.
- The bound commit sits on the fixture desk branch, not as an ancestor
  of `bp3/goal/<fixture>` — the same shape as this graph's own lands
  (6f124a6 is not an ancestor of `bp3/goal/2026-11-16-...` either);
  land merged the node ledger into the graph branch.
