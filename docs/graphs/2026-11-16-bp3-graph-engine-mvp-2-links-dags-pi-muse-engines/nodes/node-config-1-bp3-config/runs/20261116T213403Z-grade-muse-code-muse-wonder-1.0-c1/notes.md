# grade notes — exp-config-1-bp3-config @ 229a6ba

Verdict: needs_fix (code-reviewer fix_first). Decided at rungs 1-4; zero whole-tape reads.

## Why negative despite green tests
- Evidence matrix has two gated `missing` rows: `local only` (rung 3) and
  `adherence: no hand-edited state` (rung 2), both "row carried no typed evidence".
  Grade rule: any gated fail/missing => negative verdict. Lesson: a passing
  implementation still fails grade when the handoff ships no typed evidence
  for a gated case; evidence completeness is part of the deliverable.
- `Config.thresholds()` (config.ml:106) has no consumer: acceptance says
  thresholds are "honored by verdicts", but only the view honors an edit.
  Wiring (or scoping the claim to a successor exp) is owed.

## What was verified (rung 3, run not read)
- `dune build --root=. src/quest/main.exe` ok (plain `dune build` in a worktree
  walks to the conductor root and fails; use --root=. as the Makefile does).
- `./test/config.sh` -> "config tests: ok"; `./test/completion.sh` ok; shellcheck ok.
- Live `bp3 config --source`: thresholds 180/3, contexts [], derivations counted,
  config_dir = repo .git/bp3; `git status` clean at the bound commit.

## Reviewer minors (non-blocking)
- config.ml header says runs/*.json are "created at link mint", but no mint
  writer exists at this commit (mvp.1); comment states future intent.
- `ensure_dir` swallows all mkdir errors; failures surface later, misattributed.
- Test fixtures hand-write runs/*.json into the store — fine as fixtures,
  but they are not proof a verb writes them.
