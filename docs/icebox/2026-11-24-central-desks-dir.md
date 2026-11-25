---
status: frozen
date: 2026-11-24
promoted: null
---

# Central desks directory (`~/.bp3/desks/`) and delete `Makefile` `--root=.` hack

## Context

Frozen on 2026-11-24 when canceling `docs/quests/2026-11-22-bp3-is-static-across-downstream-repo-worktrees/QUEST.md` (superseded by `2026-11-23-quest-promote-release` `v0.3.0` and `91d27b1`).

Today `bp3 harness desk prepare` nests git worktrees inside the repo at `.bp3/worktrees/<run_id>` and stores desk metadata at `.bp3/desks/<run_id>.json`. Nesting a worktree inside a checkout breaks upward root-finding tools (`dune build`, `opam`, downstream pre-commit hooks): `bp3` hides this for itself via a `Makefile:7-8` hack (`$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)`), while downstream repos like `~/m/predictor` fail outright without `--root .`.

Owner direction on 2026-11-24: kill the `Makefile` `--root=.` hack and unify **all** repos (`self` and `host`) on one central machine-local directory, **`~/.bp3/desks/`**, rather than nesting inside `.bp3/worktrees/` or cluttering `~/m/` with sibling `../<repo>.desks/` directories. Agent sandbox constraints are explicitly out of scope.

## Sketch

- **Unified central desk path (`src/quest/layout.ml`, `src/quest/worktree.ml`):**
  - Default desk root: `~/.bp3/desks/<repo>-<short_hash>/<run_id>` (keyed by repo name + short hash of the repo's common git dir so same-named repos never collide).
  - Overridable via `BP3_DESKS_DIR` (used by tests for isolation, and by anyone wanting a custom path); `--path` on `desk prepare` still wins per invocation.
  - Identical rule for `self` and `host` modes — zero mode branching.
- **Move desk metadata out of the repo too:**
  - Store `<run_id>.json` metadata under `~/.bp3/desks/<repo>-<short_hash>/.meta/` (or in `bp3.sqlite` if thawed alongside the SQLite control plane) so repos never need `.bp3/` in `.gitignore` and never risk dirtying the root checkout.
- **Delete the `Makefile` hack (`Makefile:7-8`):**
  - Remove `$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)` from `DUNE_BUILD` and `DUNE_TEST`.
- **Update internal desk readers & tests:**
  - `src/quest/metrics_io.ml`: match both the new `~/.bp3/desks/...` slug and legacy `.bp3/worktrees/` slug so historical quest scrapes stay intact.
  - `src/warden/warden_io.ml`: read desk metadata from the central registry.
  - `test/g.sh` and `test/worktree.sh`: run with `BP3_DESKS_DIR` pointed at test temp dirs so tests never touch real `~/.bp3`.
- **Skill alignment (`skills/`):**
  - Drop "host mode works directly in the repo / has no desk" prose from the conducting skills (`induct` / `induct-inline`, `using-bp3`) and re-render.
- **Deliberately not added:**
  - No agent sandbox plumbing (no `.claude/settings.json` `additionalDirectories` merge; explicitly ignored per owner direction).
  - Do not mix worktrees + `_build/` caches into `~/.local/share/bp3/` (which holds installed skills/scripts and `bp3.sqlite`).

## Blockers

- **Backwards compatibility for historical metrics:** `src/quest/metrics_io.ml` currently derives pi/Claude transcript slugs from `<repo>/.bp3/worktrees/`; keep matching legacy slugs alongside the new `~/.bp3/desks/` path so re-scraping old quests doesn't regress.
- **Existing open desks at upgrade:** Decide at thaw whether `desk list` / `desk release` falls back to legacy `.bp3/desks/` during transition or assumes no open desks at cutover.
- **Downstream `_opam` / hook lookup:** Moving a desk outside `~/m/predictor` means opam's upward `_opam` lookup won't find the root checkout's switch; verify whether `predictor`'s `.githooks/pre-commit` needs `git rev-parse --git-common-dir` or works via the default switch + `dune.lock`.
- **Sequencing with `2026-11-23-codebase-diet`:** `codebase-diet` cleans up `worktree.ml`/`names.ml` and consolidates `induct-inline` -> `induct`; thawing after `codebase-diet` avoids touching the old 4-skill layout and pre-`Names` error strings.

## Promotion trigger

Thaw when ready to delete the `Makefile` `--root=.` hack or when starting a quest in `~/m/predictor` (or another downstream repo) that needs isolated quest/grade desks.
