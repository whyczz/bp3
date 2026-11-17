# Verify notes — exp-config-1-bp3-config @ 229a6bacc7d044c1d35745ca88e3138d024117d1

Fresh checks run in this session (rung 3, worktree at bound commit, status clean):
- `./test/config.sh` -> `config tests: ok` (exit 0). Covers zero setup, viewable,
  local-only git-clean assertions, thresholds local, worktree-shared tree,
  by-session rebuild, derivations >= 1.
- `BP3_Q_BIN=_build/default/src/quest/main.exe ./bin/bp3 config --source` ->
  ok:true, config_dir under `.git/bp3`, thresholds 180/3, derivations 258.
- `git rev-parse HEAD` = bound commit; `git status --porcelain` empty.

Verdict is fail on evidence discipline, not on function: the grade matrix
carries two gated rows with verdict `missing` and no typed evidence —
"local only" (rung 3) and "adherence: no hand-edited state" (rung 2), each
"row carried no typed evidence" (the audit's empty `git status` quotes do
not count as typed evidence). Per the grade rule, any gated fail/missing
row means the work is not correct: cast the negative verdict. Fresh test
green does not rewrite the graded matrix rows.

Ladder discipline: decided at rungs 1-3 (records, commit diff, fresh test
runs). Zero whole-tape reads; no rung-5 escalation.
