# grade run notes — exp-config-1-bp3-config c2

- Reviewed at bound commit 3c47fe5 per code-reviewer: claims from EXPERIMENT.md
  (zero setup, viewable, local only, thresholds local, survives worktrees,
  derivations folded in) walked against config.ml/main.ml and test/config.sh.
- Cycle-2 fix verified: ensure_dir now swallows only EEXIST (other mkdir
  failures raise at site; EACCES test covers it), and the thresholds claim is
  scoped in header + help text to store/view, enforcement deferred to
  mvp.1/mvp.3. Removed dead Config.thresholds with no callers.
- Rung 3 run, not read: dune build ok, ./test/config.sh -> "config tests: ok",
  ./bin/bp3 config --source -> thresholds 180/3, empty contexts, derivations 262.
- No findings at critical/major/minor severity; comments agree with code.
- Verdict: ship.
