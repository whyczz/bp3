# Grade notes — exp-followup-2-workflow-birth cycle 2 (bound e37190a)

Verdict: ship (code-reviewer procedure; correctness, design, tests, comments).

- Rung 1-2: EXPERIMENT.md acceptance (stale render, mvp.1 replay, fresh render,
  all workflows; amendment: desk reads, context threading, claim-session tape,
  regression fixtures, foreign-dialect conduct) all gated here; cycle-2 adds the
  real-conduct row. Bound commit adds conduct-cycle2.md; implementation at
  6f124a6 reviewed in full diff.
- Rung 3 (run, not read): skills check fresh ok; backdated bp3g-grade render
  refuses E_RENDER_STALE naming render+source, restored fresh; all five workflow
  test files pass individually; harness.sh all checks passed; skills.sh ok
  (134 assertions). Fixture graph 2026-11-17-followup2-fixture read back landed,
  commit fafcc14, matching the conduct record (0 read refusals).
- Rung 4: comments agree with code (freshness=byte equality, context never
  silently dropped, claim-session tape resolves first); no lying comments, no
  hand-edited renders (all four renders byte-identical to sources).
- Conduct caveat (non-blocking): single sequential session stamped the fixture
  grade cast with the verify run-id (W_CONTEXT_ENV_MISMATCH); verdicts, bound
  commit, and state sequence exact, and the acceptance gates on landed state
  with zero read refusals.
- Tree note: only untracked file is harness-written .bp3-context.json.
- No whole-tape (rung 5) reads were needed or used.
