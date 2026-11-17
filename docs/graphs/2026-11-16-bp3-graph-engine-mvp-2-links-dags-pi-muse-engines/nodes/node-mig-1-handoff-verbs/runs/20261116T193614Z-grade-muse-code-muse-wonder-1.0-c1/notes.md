# grade notes — exp-mig-1-handoff-verbs (cycle 1)

Verdict: ship. Decided at rungs 1-3; no tape reads (5a/5b untouched).

- Rung 1: EXPERIMENT.md acceptance = 5 gated cases, no deferred rows,
  no open design questions. Quest reads handed_off/cycle 1 at bound
  commit 4419672; old quest 2026-11-14 exp-1 folds landed.
- Rung 2: compat lives only in src/quest/store.ml:156-160
  (fold_edge/fold_state_name) with a comment that agrees with the
  code; zero docs/quests paths in HEAD~1..HEAD; no old-verb edges
  in main.ml/harness.ml.
- Rung 3 (run, not read): `make check` exit 0 incl. q tests and
  skills tests; old verb `submit` refuses E_USAGE unknown edge
  (exit 2, observed live); renders differ only by generated header.
- Adherence: ledger handoff line written by the child directly,
  run_id 20261116T191513Z-... stamped from env; build run folder
  has notes.md + tape.log (339 lines); tree clean at bound commit.

Lesson: probe the refusal with --reason attached, or the reason
guard answers first and the unknown-edge check never runs.
