# followup.5 pure-grade — author (handoff) run notes, cycle 3

Run: 20261118T031254Z-handoff-muse-code-muse-wonder-1.0-c3
Bound commit at dispatch: 31b7c740a485bd43d10edfec07e226f74df3c518
Harness: muse-code / muse-wonder-1.0 (link claim returned the expected run_id)

## Task

Named mechanical fix from the grade of 31b7c74: add `--verify-verdict`
and `--mechanical` to the `_bp3_flags` lists in `completions/_bp3` and
`completions/bp3.bash` (matching `src/graph/main.ml` `parse_flags`), so
`test/completion.sh` passes and `make check` exits 0 at the fix commit.
Mark the fix RESOLVED in the fix commit.

## Lessons

- Bound-commit grading matters: HEAD already carried the flags fix in
  follow-up 0ee41e2, but the bound commit 31b7c74 does not contain it,
  so the cycle-2 grade correctly failed the regression row there.
  A later-branch fix never retro-passes a bound grade; the fix must
  ride the handoff-bound commit's ancestry.
- The completion parity test (`test/completion.sh`) pins both
  directions: every completed flag must parse in `main.ml`, and every
  parsed flag must be completed. Adding a parser flag without the
  completion lists is a gated regression, masked only while an
  earlier gate step fails first.
- Grade-blocking porcelain: pending cycle-2 run notes
  (node/grade/verify) are committed here as deliberate evidence;
  tapes stay gitignored.

## Verification (this run, at the fix commit)

- `./test/completion.sh` -> `completion tests: ok` (exit 0).
- `make check` -> exit 0 (`MAKE_CHECK_EXIT:0` in tape.log; all gate
  steps ok, including dogfood-parallel, bp3g, completion, release,
  install).
