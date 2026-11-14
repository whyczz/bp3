# Check run — exp-6-hooks, cycle 2

Bound commit: `31f362b755f581469cbf865f812f749467fa3f5c`
(`fix(q): stale-gated run_unsettled sweep and settings.json hook delivery`)

## Claims checked (verify stance: fresh output only)

- Exp acceptance = all cases in `test/hooks.sh` — ran in a clean
  clone checked out at the bound commit: `hooks tests: ok`.
- Hook registration (`bp3 skills install` writes
  `.claude/hooks.json` and merges into `.claude/settings.json`) —
  `test/skills.sh`: `skills tests: ok (46 assertions)`; assertions
  at lines 66–73 cover both files and preserving existing keys.
- Project gate `make check` at the bound commit — exit 0:
  shellcheck + `node --check` clean, check-skills ok (32 files),
  dune build ok, `q tests: ok`, `tape tests: ok`,
  `induct-exp tests: ok`.

Cycle-2 fix coverage corroborated in `test/hooks.sh`: backdated
binding swept as `run_unsettled`, fresh parallel bindings not
swept, ageing only one of two parallel bindings sweeps only it.

## Lessons

- Judging the bound commit in a fresh clone keeps run tapes and
  parallel-run dirt in the main worktree from polluting the check.
- HEAD is 3 tape-only commits past the bound commit; the code
  diff bound..HEAD is empty, but the clone removes that doubt
  instead of arguing it.

Verdict: pass.
