# Run Log — `2026-11-25-draft-desk-guard`

Living build log for [QUEST.md](QUEST.md) (branch `quest/2026-11-25-draft-desk-guard`, base `2ca58e09` on top of `v0.6.0` `central-desks-dir`).

## Nodes & cycles

| Node | Commit | Cycles | Verdict | Receipt (`make check-full` / `red-first`) |
|---|---|---|---|---|
| `node-draft-1-draft-desk-cli` | `0de68c1f` | 1 | `ship` (`4db71e89`) | 25/25 ok (31.3s), `red-first: red (ocaml)`, +134/-2 test lines |
| `node-release-1-cas-merge-release` | `645f6ddb` | 1 | `ship` (`92400dbc`) | 25/25 ok (53.6s), `red-first: red (ocaml)`, +123/-21 test lines |
| `node-skills-1-planning-worktree-guards` | `e5d636f5` | 1 | `ship` (`a212cd64`) | 25/25 ok (44.3s), `red-first: red (skills)`, +19/-0 test lines |

## Measured scorecard

| Metric | Observed |
|---|---|
| Nodes landed / total | 3 / 3 (`goal_fin`), all on cycle 1 |
| Cold grades (`brief_verbatim` / `brief_edited` / `mismatched`) | `3 / 0 / 0` (`self_checked: 3`) |
| Author wall / active median (`metrics r`) | `377s` / `298s` (`sum: 1121s` / `822s`) |
| Grade wall median (`metrics r`) | `234s` (min `161s`, max `3270s` incl. `2887s` external stall on `4db71e89`) |
| Live dogfood (`bp3 release --dry-run` against moved `master` `ba2bd5db`) | `strategy: "merge"`, `drift_kind: "doc_only"`, `conflicts: []`, `tag: "v0.7.0"` |

## Build notes & lessons

- **Live validation of the quest's own thesis:** Mid-build, another parallel session edited files directly on `/Users/whycz/m/bp3` (`master`) and committed `ba2bd5db` (`docs/quests/*`). Running `./bin/bp3` from inside the central quest desk isolated our `handoff`/`grade`/`land` edges cleanly from the dirty main checkout, and `./bin/bp3 release 2026-11-25-draft-desk-guard --dry-run` automatically recognized `ba2bd5db` as `drift_kind: "doc_only"` with `strategy: "merge"` and `conflicts: []` instead of refusing `E_NOT_FAST_FORWARD`.
- **Cache invalidation around rebase/CAS:** `Gitx.tip_cache` caches `ref_tip` per process; calling `invalidate_ref_caches ()` right after `git rebase` and after failed CAS attempts in both `worktree.ml` and `release_io.ml` prevents stale SHA reads.
- **Grader follow-ups carried into [FEEDBACK.md](FEEDBACK.md):**
  - `worktree.ml`: atomic CAS delete (`update-ref -d`) for non-HEAD `--target` branch cleanup (`4db71e89`).
  - `release_io.ml`: merged stderr/stdout capture for `verify_merged_tree` subprocesses + fail-closed `git_drifted_files` (`92400dbc`).
  - `skills/red-ink/SKILL.md`: guard placement (minor).
