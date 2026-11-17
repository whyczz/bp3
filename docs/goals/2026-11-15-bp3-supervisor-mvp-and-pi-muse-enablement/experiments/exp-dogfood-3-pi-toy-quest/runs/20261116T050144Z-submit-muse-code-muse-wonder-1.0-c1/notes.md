# Run notes — exp-dogfood-3-pi-toy-quest c1 (muse author, pi demo child)

## What was built

- One pi experiment Run `20261116T050354Z-demo-pi-gpt-6.1-sol-c1`
  (pi 1.5.0, `pi -p --mode json`, model gpt-6.1-sol) built
  `flappy.html` (6289 bytes, three.js Flappy Bird) in its own
  run folder `runs/20261116T050354Z-demo-pi-gpt-6.1-sol-c1/`.
  Same `flappy` spelling as dogfood.1; the engine is the one
  changed variable, as the exp asks.
- Launcher discipline followed: `record-init` (harness pi,
  live pid 55778) before the child's work was observed,
  `bind-tape` after exit, both called by this author as
  launcher — the pi child wrote no proof of itself.
- `BP3_RUN_ID` arrived via environment for both Runs: the
  submit Run (stamped by bp3 into the submit verdict/ledger)
  and the pi child (exported by the launcher; its InitRecord
  carries the id).

## Proof observed

- `bp3 harness watch --run-id <pi-run>`: outcome `settled`,
  lifecycle `finished`, exit 0.
- `bp3 harness supervisor <quest>`: the pi Run's row is
  `finished` in every lifecycle_change row and in the final
  verdict; the derived-state cache shows `finished` with
  `warnings: []`, `pid_alive: false`. Extracted into
  `pi-derivation.json` in this run folder.
- Artifact smoke: module script extracted from `flappy.html`
  (5225 bytes, imports `three`), `node --check` exit 0.

## Lessons / findings

- A pi Run derives `finished` only with a recorded pid:
  pi finish evidence (`stopReason: stop` on the last entry)
  plus pid-dead gives exit observed. record-init must name
  the live pid; the launcher recorded it ~1s after spawn,
  before pi's first assistant entry.
- `find-tape --run-id <pi-run>` returns E_NOT_FOUND even
  after bind-tape: the scan needs a literal `BP3_RUN_ID=<id>`
  mention, and pi tapes carry the id only as prose. The fold
  and watch honor the binding row; scan resolution does not.
  This is backtest.2 finding F1 (pi tapes bind sessions,
  never Runs) seen live — named here for dogfood.2.
- `bp3 harness supervisor <quest> --engine pi` is E_USAGE
  (contradicts the quest's muse-code InitRecords); the
  quest-wide supervisor without `--engine` is the drive.
  Its outcome was `timeout` only because historical muse
  Runs sit at `init`; the pi row itself is `finished`.
- Bulk pi `--mode json` stdout (660KB of event echoes) was
  verified then removed; the session tape under
  `~/.pi/agent/sessions/` remains the pi Run's WAL.
