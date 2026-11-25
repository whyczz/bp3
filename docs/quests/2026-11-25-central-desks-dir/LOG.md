# Run log — 2026-11-25-central-desks-dir

Quest: [QUEST.md](QUEST.md)  
Branch: `quest/2026-11-25-central-desks-dir`  
Mode: `/induct-yolo` (no-human rails)

## Nodes

| Node | Wave | Lane | Status | Cycle | Commit | Notes |
|---|---|---|---|---|---|---|
| `node-desks-1-central-layout-and-worktree` | 1 | high-blast-radius | landed (`node_fin`) | 1 | `87f4edb` | `check-full` 25/25 (30.4s), `red-first: red (ocaml)`; 2 minor follow-ups |
| `node-cleanup-1-drop-makefile-root-hack` | 2 | standard | landed (`node_fin`) | 1 | `2ccc4bf` | `check-full` 25/25 (30.6s), `red-first: red (check-tiers)` from central desk; 1 minor follow-up |
| `node-desks-2-metrics-dual-slug` | 2 | standard | landed (`node_fin`) | 1 | `e9f2c23` | `check-full` 25/25 (30.3s), `red-first: red (metrics)`; 0 follow-ups |
| `node-skills-1-unify-host-and-self-desk-prose` | 2 | micro | landed (`node_fin`) | 1 | `b9356a4` | `check-full` 25/25 (30.5s), `red-first: red (skills)`; 0 follow-ups |

## Build notes & lessons

- **2026-11-25 (Wave 1 -> Wave 2 migration):** After `desks.1` (`87f4edb`) landed, the legacy `.bp3/worktrees/2026-11-25-central-desks-dir` quest desk was released via the newly built `desks.1` binary (live-testing legacy `.bp3/desks/` fallback release) and re-prepared into `~/.bp3/desks/bp3-3951d199/quests/2026-11-25-central-desks-dir`. All Wave 2 nodes (`cleanup.1`, `desks.2`, `skills.1`) were authored inside the central quest desk and graded in sibling central grade desks under `~/.bp3/desks/bp3-3951d199/runs/...`.
- **`do_remove` worktree-context bug fixed in `desks.1`:** `worktree.ml:141-145` previously compared `git rev-parse --show-toplevel` against `canon abs`, which falsely refused `worktree exit` with `E_MAIN_WORKTREE` when invoked inside a desk without a pinned `BP3_ROOT`. Fixed by comparing `main_root ()` and running `git -C <main_root> worktree remove`, covered in `test/worktree.sh` and `test/config.sh`.
- **`realpath_best` in `desks.2`:** `metrics_io.ml` walks up to the longest existing ancestor before calling `Unix.realpath`, ensuring macOS `/var` vs `/private/var` symlinks still match central desk transcripts even before a desk directory exists or after it has been released.
- **`scripts/red-first` commit type catch on `cleanup.1`:** Initial `refactor(cleanup.1)` subject was flagged by `scripts/red-first` because tightening `scripts/check-gates` changes behavior (tests fail on parent); amended to `fix(cleanup.1)` (`2ccc4bf`) before handoff.
- **Non-blocking minor grader follow-ups:**
  - `desks.1`: `Layout.repo_desks_dir "/" key` yields `"//<key>"` because `strip_trailing_slashes "/"` preserves `"/"` before concatenating `"/" ^ key`; `test/g.sh` and `test/warden.sh` gained `BP3_DESKS_DIR="$work/desks"` isolation outside `NODE.md`'s Output list.
  - `cleanup.1`: `scripts/check-gates` inspects expanded `make -n` output, so a `$(CURDIR)`-conditional `--root=.` only expands when `CURDIR` matches.
