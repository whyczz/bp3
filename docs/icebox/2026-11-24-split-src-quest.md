---
status: frozen
date: 2026-11-24
promoted: null
---

# Split `src/quest/` into domain libraries under `src/`

## Context

Frozen 2026-11-24 during Round 6 (Functions) of `/red-ink` on
`docs/quests/2026-11-23-sqlite-control-plane/QUEST.red-ink.md`.
Owner call verbatim: `"src/db pls, not src/quest"`, `"also stop putting everything in quest"`,
`"if we need to refactor, let's do that now, e.g. /icebox it, and lets finish this redink"`.

Today `src/quest/` has grown into a 23-file, **10,193 LOC** junk drawer mixing
unrelated domains behind one `(library (name bp3_quest) (wrapped false))`:
- CLI entrypoint (`main.ml`, `cli.ml`, `names.ml`)
- Core git/layout/clock plumbing (`gitx.ml`, `layout.ml`, `clock.ml`, `config.ml`)
- Quest/node FSM (`store.ml`, `render.ml`, `brief.ml`, `hooks.ml`)
- Release engine (`release.ml` 361L, `release_io.ml` 715L)
- Transcript & metrics (`tx.ml`, `agy_tx.ml`, `claude_tx.ml`, `pi_tx.ml`, `metrics.ml`, `metrics_io.ml`)
- Worktrees / harness (`worktree.ml`, `harness.ml` 2,812L — `harness.ml` slated for deletion in `2026-11-23-codebase-diet`)
- Test suite runner (`suites.ml`, `run_suites.ml`)

Meanwhile `src/warden/` (`bp3_warden`) proved the clean multi-library dune
pattern, and `2026-11-23-sqlite-control-plane` puts new doors in dedicated
`src/db/`, `src/repo/`, and `src/ticket/` libraries instead of adding to `src/quest/`.

## Sketch

Split `src/` by domain with strict one-way dune dependencies (no cycles, zero
behavior change — pure file moves + dune stanzas):

```text
src/
  core/     (bp3_core)    — gitx.ml, clock.ml, layout.ml, names.ml, util.ml
  db/       (bp3_db)      — db.ml, db_cli.ml                  (sqlite-control-plane)
  repo/     (bp3_repo)    — repo_store.ml, repo_cli.ml        (sqlite-control-plane)
  ticket/   (bp3_ticket)  — ticket_store.ml, ticket_cli.ml    (sqlite-control-plane)
  desk/     (bp3_desk)    — worktree.ml (+ slim desk CLI)
  tx/       (bp3_tx)      — tx.ml, agy_tx.ml, claude_tx.ml, pi_tx.ml
  metrics/  (bp3_metrics) — metrics.ml, metrics_io.ml
  quest/    (bp3_quest)   — store.ml, render.ml, brief.ml, hooks.ml, config.ml
  release/  (bp3_release) — release.ml, release_io.ml
  warden/   (bp3_warden)  — warden.ml, warden_io.ml           (already separate)
  suites/   (bp3_suites)  — suites.ml, run_suites.ml          (executable run_suites.exe)
  cli/      (main.exe)    — main.ml, cli.ml                   (thin dispatch over all doors)
```

Deliberately not: no FSM or CLI behavior changes, no `bin/bp3` wrapper removal
(that belongs to `2026-11-23-single-cli.md`), and no feature work bundled in.

## Blockers

- **Build path references to `src/quest/main.exe` and `src/quest/run_suites.exe`:**
  `Makefile`, `bin/bp3` (`ENGINE_SRC="src/quest"`, `repo_mode` checks `src/quest`
  + `bin/bp3`), `scripts/run-suites`, `scripts/install-bp3.sh`, `test/mode.sh`,
  and `src/quest/gitx.ml:196` (`repo_mode`) all check or exec `src/quest/...`.
  Moving `main.exe` out of `src/quest/` requires updating `Layout.engine_src` /
  `bin/bp3` cleanly (or keeping a thin `src/cli/main.exe` with `Makefile`/`bin/bp3`
  updated in one commit).
- **Sequencing with `2026-11-23-codebase-diet`:** `harness.ml` (2,812 LOC) is
  scheduled for deletion there; splitting before `codebase-diet` would move dead
  code, or `split-src-quest` can run right before/alongside `codebase-diet` and
  leave `harness.ml` untouched until retired.
- **`test/unit/dune` library list:** Must link the split internal libraries
  (`scripts/check-constraints` auto-detects every internal dune library name).
- **Hidden cross-module calls:** Verify `claude_tx.ml` -> `Harness.epoch_of_iso`
  (`src/quest/claude_tx.ml:27`) is moved into `bp3_core` or `bp3_tx` so `bp3_tx`
  has zero upward dependency on `bp3_quest`/`harness`.

## Promotion trigger

Thaw immediately when the owner wants to clean up `src/` before starting
`sqlite-control-plane` (or right after `codebase-diet` deletes `harness.ml`),
so `main.exe` lives in `src/cli/` and every domain owns its own `src/<domain>/`
directory.
