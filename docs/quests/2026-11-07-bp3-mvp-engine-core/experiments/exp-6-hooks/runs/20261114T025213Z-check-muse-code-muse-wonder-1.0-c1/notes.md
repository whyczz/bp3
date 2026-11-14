# exp-6-hooks check run — lessons

- Verify stance: judged only on fresh output. Ran the project gate
  `make check` in this session; all stages green (lint, skills 43
  assertions, q, tape, hooks, induct-exp), exit 0.
- HEAD (b091c18) code is byte-identical to the bound commit cc115c5:
  `git diff cc115c5..HEAD` touches only the submit run tape.log, so
  the fresh gate run validates the bound changeset, not a drifted tree.
- No EXPERIMENT.md exists for exp-6; acceptance lives in
  test/hooks.sh (fail-open, binding, usage, settle cases) plus the
  bound commit message. The hooks suite is the exp-specific gate.
- Verdict: pass on cc115c5.
