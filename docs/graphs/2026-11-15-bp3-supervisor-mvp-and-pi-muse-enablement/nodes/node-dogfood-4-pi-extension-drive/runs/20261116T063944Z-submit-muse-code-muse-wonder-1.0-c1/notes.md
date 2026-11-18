# Run notes — exp-dogfood-4-pi-extension-drive c1 (muse author, pi conductor drive)

## What was driven

- A pi conductor session (pi 1.5.0, model openai/gpt-6.1-sol,
  `bp3-pi` loaded via `-e extensions/bp3-pi/index.ts`) drove the
  toy work through its own tools only, as the exp asks:
  `spawn_run` once → `await_runs` → `list_runs`. The verbatim
  drive is `drive.jsonl` in this folder (attempt 1 kept as
  `drive-attempt1.jsonl`; see Lessons).
- `spawn_run(role=author, edge=demo, cycle=1)` returned child Run
  `20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1`, pid 97482,
  exit 0. The dispatcher called `record-init` (live pid) before
  work and `bind-tape` after exit; the conductor called neither
  by hand and spawned no shell pi.
- The pi child built `flappy.html` (8439 bytes, three.js Flappy
  Bird) in its own Run folder
  `runs/20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1/`, reading
  its run id from the `BP3_RUN_ID` env the dispatcher set.
- `await_runs` reported outcome `settled`; `list_runs` showed the
  child Run `finished`. The derived-state cache
  (`pi-derivation.json` here) is `finished` with
  `warnings: []`, `pid_alive: false`.
- Artifact smoke: module script extracted from `flappy.html`
  (7059 bytes, imports `three`), `node --check` exit 0.

## Lessons / findings

- Worktree root resolution bites the drive: the dispatcher's
  `resolveRepoRoot` uses the git common dir's parent, which in a
  quest worktree is the main checkout (master, older `bin/bp3`
  without the `harness` door), so attempt 1's `record-init`
  refused `E_BP3_FAILED`. The retry pinned the dispatcher's bp3
  via `BP3_PI_BP3_BIN` to this worktree's `bin/bp3` and gave the
  child an absolute artifact path (its cwd is the resolved
  root). The extension itself needed no change; the gap is
  worktree-shaped roots, worth a follow-up naming.
- `await_runs`' watch verdict carried `W_SUPERVISOR_BLIND`
  (watch's tape scan finds no tape pointer for a pi Run — the
  backtest.2 F1 shape) while the folded derivation itself is
  `finished` with `warnings: []`. The blind warning rides the
  watch relay, not the lifecycle fold.
- `BP3_RUN_ID` arrived via environment for both Runs: this
  submit Run (stamped by bp3 into the submit verdict/ledger) and
  the pi child (set by the dispatcher; its InitRecord carries
  the id, model openai/gpt-6.1-sol, thinking medium from the
  author role file).
