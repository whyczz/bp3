# Run log — 2026-11-25-desk-auto-cleanup

Quest: [QUEST.md](QUEST.md)  
Branch: `quest/2026-11-25-desk-auto-cleanup`  
Mode: `/induct-yolo` (no-human rails)

## Nodes

| Node | Wave | Lane | Status | Cycle | Commit | Notes |
|---|---|---|---|---|---|---|
| `node-clean-1-release-auto-cleanup` | 1 | standard | landed (`node_fin`) | 2 | `c30eb4b4` | c1 `needs_fix` (2 major: pure unit tests + missing-desk `worktree prune` & `canon_best` on `exclude_paths`); c2 `ship` (0 findings, 25/25, `red-first: red (ocaml)`) |
| `node-clean-2-desk-prune-verb` | 2 | standard | landed (`node_fin`) | 1 | `5bbbb95a` | c1 `ship` (0 findings, 3 minor follow-ups, 25/25, `red-first: red (worktree)`) |
| `node-skills-1-document-auto-cleanup-and-prune` | 3 | micro | landed (`node_fin`) | 1 | `4a82dd73` | c1 `ship` (0 findings, 0 follow-ups, 25/25, `red-first: red (skills)`) |

## Build notes & lessons

- **2026-11-25**: Quest initialized on `master` `ba2bd5db` (`v0.6.0`), authoring directly in central desk `~/.bp3/desks/bp3-3951d199/quests/2026-11-25-desk-auto-cleanup`.
- **`clean.1` macOS `/var` symlink lesson**: `Unix.realpath` raises `ENOENT` on a just-removed desk leaf path, so `Layout.prune_empty_parents` and `exclude_paths` use `canon_best` (walking up to longest existing ancestor before `Unix.realpath`).
- **`clean.1` missing-desk prune lesson**: When a quest desk directory was already deleted on disk, `git branch -d` refuses until `git worktree prune` clears the stale worktree registration; fixed in c2 (`c30eb4b4`) and locked in `test/release-door.sh`.
- **2026-11-25**: All 3 nodes reached `node_fin` (`rollup: landed`, `fin: goal_fin`); 4/4 cold grades verbatim (`brief_verbatim: 4, brief_edited: 0`), zero open grade desks. Ready for owner `/warden` and `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-desk-auto-cleanup`.
