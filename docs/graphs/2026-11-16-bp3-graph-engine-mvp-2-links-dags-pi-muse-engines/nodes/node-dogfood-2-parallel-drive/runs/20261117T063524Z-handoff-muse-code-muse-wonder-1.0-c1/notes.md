# exp-dogfood-2-parallel-drive — handoff run notes

- Name chosen: `test/dogfood-parallel.sh`, reusing the repo words
  `dogfood` (the exp family, as in `test/dogfood-link.sh`) and
  `parallel` (this exp's title, parallel-drive).
- The first parallel drive failed for a real product reason:
  two `bp3 harness link mint` calls in the same second generated
  the same run-id (`<ts>-handoff-<harness>-<model>-c1`), and the
  check-then-rename write let the second mint overwrite the
  first run config, so both links pointed at one run and one
  claim lost with the other node's facts. That is the exact
  ready-set case this exp exists to prove.
- Fix at the root in `src/quest/harness.ml`: mint now writes
  the minted run config with `O_EXCL` and retries on the next
  second's candidate on `EEXIST`; an explicit `--run-id` that
  already exists still refuses `E_EXISTS`. The run-id spelling
  is unchanged, so existing parsers (edge = second dash field,
  cycle = last field) and the Pi dispatcher's
  `-<model>-c<cycle>` suffix keep working.
- `test/dogfood-parallel.sh` is the drive: one ready-set
  `[flappy-day, flappy-night]`, parallel author workers in
  separate desks claiming separate links, overlapping
  timestamp intervals, per-session context resolving to its
  own node, desk/branch isolation, full handoff/grade/verify
  matrix per node, serial land with the second land building
  on the first tip, and a scorecard computed from worker
  timestamps plus the bp3 rollup (`ready_wall_ms` <
  `serial_sum_ms`). Tokens are reported as `null` with a named
  cause: the rollup has no per-node token field, so none are
  invented. A same-file conflict fixture lands serially with
  `land_conflict: true` and no overwrite, and a blocked node
  starves only its dependents.
- Pi tree death/revival and the Muse blocked bubble are not
  re-proved here; they are covered by `test/pi-tree.test.mjs`
  and `test/blocked.sh`, both in `make check`.
- Observed on the passing drive: ready wall 3955 ms vs serial
  sum 6890 ms (saved 2935 ms); per-node rollup wall 2 s each.
