# Run notes — exp-dogfood-1-muse-toy-quest c2 (muse)

## What was built

- `flappy.html` in this run folder: the three.js Flappy Bird
  demo carried over from c1 (same `flappy` spelling), so the
  artifact plus traces live in this exp's `runs/` as the exp
  asks. Module script extracted and verified with
  `node --check` (pass).
- Child briefs no longer carry the first-command prefix
  ritual: `tapePreamble` in `induct-exp.js`,
  `induct-grade.js`, and `quest-land.js` (skills source plus
  installed `.agents/workflows` copies via
  `bp3 skills install`) now states that `BP3_RUN_ID` and
  friends arrive via environment and `bp3` stamps them into
  verdicts and ledger lines. `envPreset` stays only on the
  `bp3 q u` edge commands and `record-init`, where it sets
  the environment for that call. The audit adherence row is
  renamed `env-set run-id` to match.
- Tests updated beside the change: `induct-exp`,
  `induct-grade`, and `quest-land` mock-host tests assert
  no `Prefix your FIRST` instruction and the
  `arrive via environment` statement; edge commands still
  assert `BP3_RUN_ID=`. `./test/induct.sh`: all three ok.

## Lessons

- The c1 grade failed on brief text, not the demo: when an
  acceptance case names generated briefs, the generator is
  the owned module and the fix belongs there, with its
  committed tests changed in the same commit.
- `full drive` (toy exp `exp_fin`/landed) is not the author
  child's edge: submit moves `todo -> submitted`; grade and
  land steps own the rest. This run does not claim it.
- Verification is still static for the demo: no browser was
  opened, so `page opens` remains for a grader to confirm
  visually. Pre-existing dirty files from other exps were
  left untouched; only this run's files were committed.
