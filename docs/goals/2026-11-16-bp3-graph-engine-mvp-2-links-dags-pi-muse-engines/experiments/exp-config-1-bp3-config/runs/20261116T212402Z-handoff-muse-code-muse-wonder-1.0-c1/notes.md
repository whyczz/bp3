# config.1 (bp3-config) — author run notes

Built the machine-local bp3 config store and its view door:

- New `src/quest/config.ml` (module `Config`): `config_dir` resolves
  `<git-common-dir>/bp3/` (canonicalized, so `/var` vs `/private/var`
  spellings and every worktree agree); `ensure_config` creates the
  tree (`config.json`, `runs/`, `links/`, `by-session/`, `desks/`,
  `run-lifecycle-derivations/`) with defaults and never overwrites an
  existing `config.json`; run configs fold into contexts; the
  by-session index is rebuilt from `runs/` on every view; a torn run
  config is skipped, never folded.
- `bp3 config [--source] [--format json|table]` door in `main.ml`
  (+ `bin/bp3` dispatch, completions, `config` as a reserved slug).
  `config.json` holds machine settings only
  (`thresholds.setup_slow_s=180`, `thresholds.depth_cap=3`, the
  mvp.3/mvp.1 gates); contexts are views, never stored there.
  `--source` names the writing verb (`link mint`/`link claim`) and
  timestamp per context. Outside a git repo: `E_NOT_FOUND`.
- First-write wiring: `harness record-init` and `harness desk
  prepare` now call `ensure_config`, so the tree appears on the
  first bp3 write with zero setup.
- `test/config.sh` (wired into `make check` + shellcheck) covers:
  help/strict-argv parity, outside-git refusal, first-write tree,
  contexts + provenance, by-session rebuild after deletion, torn
  config tolerance, local threshold edits honored, desk-prepare
  first write, worktree-shared tree, legacy doors failing open.

Verification: `test/config.sh` ok, `test/completion.sh` ok, full
`make check` exit 0 in this worktree.

Lessons:

- git-common-dir spelling differs by entry point (relative `.git`
  from the main worktree, canonical absolute from a linked one);
  canonicalize once in `config_dir` or worktrees disagree on the
  store's name while sharing its files.
- The config door must not read state for `-h`, and usage errors
  must not create the tree; both are asserted in the fixture.
- Nothing needed migrating: derivations already lived under the
  tree, and desk records stay where worktree put them — this exp
  names and views the store rather than moving it.
