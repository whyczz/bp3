# Feedback & Warden Audit — `2026-11-25-draft-desk-guard`

## Human post-land feedback

- Owner direction during framing upgraded the design from a pessimistic active-quest runway freeze (which would starve drafts at 5+ parallel quests) to a 3-node **Tiered CAS** model (`draft.1 -> release.1 -> skills.1`): immediate CAS rebase landing for drafts + in-memory `git merge-tree --write-tree` + deterministic verification + 2-parent merge commits in `bp3 release`.
- Live dogfood bonus: while `draft-desk-guard` was building, another session landed `ba2bd5db` (`docs/quests/*`) on `master`, and `./bin/bp3 release 2026-11-25-draft-desk-guard --dry-run` immediately validated the new path (`strategy: "merge"`, `drift_kind: "doc_only"`, `conflicts: []`, `tag: "v0.7.0"`).

## Warden deterministic summary

Run: `./bin/bp3 warden 2026-11-25-draft-desk-guard` (2026-11-25, `sessions_scanned: 4`).

- **Counts:** `total: 2`, `by_layer: {git: 2, session: 0}`, `by_rule: {grade_inversion: 1, cycle_outlier: 1}`.
- **Metrics rollup (`bp3 q 2026-11-25-draft-desk-guard metrics r`):** 3/3 grades measured (`self_checked: 3`, `mismatched: 0`, `brief_verbatim: 3`, `brief_edited: 0`), 3/3 author windows measured (`author_wall_s` median `377s`, `author_active_s` median `298s`; `grade_wall_s` median `234s`).

| # | Rule | Layer | Sev | Node / Cycle | Evidence ref | Audit (TP/FP) | Root cause |
|---|---|---|---|---|---|---|---|
| 1 | `grade_inversion` | git | major | `draft.1` | `metrics:node-draft-1-draft-desk-cli` | **FP** | Grader `4db71e89` hit two external `ERROR_MESSAGE` stalls (`20:00:29Z -> 20:38:25Z` = 2276s and `20:38:29Z -> 20:48:40Z` = 611s; 2887s total idle out of 3270s wall; `grade.tool_s = 272s`, active ~383s vs `1.5x * 450s = 675s`). |
| 2 | `cycle_outlier` | git | major | `draft.1` c1 | `metrics:node-draft-1-draft-desk-cli:c1` | **FP** | Same 2887s external stall in grader `4db71e89` (`grade_wall_s` measures raw wall clock instead of `grade.active_s`). Second consecutive quest hitting `docs/icebox/2026-11-24-grade-active-s-warden.md`. |

## Proposals (`<= 3`, ranked by ROI)

1. **Atomic CAS branch delete for non-HEAD `--target` in `Worktree.do_land_draft`** (`src/quest/worktree.ml`, `test/worktree.sh`) — *Small fix (2 files).*
   - **Evidence:** Cold grader `4db71e89` follow-up #1 (verified in adversarial probe): `git -C mr branch -d draft/<slug>` checks reachability against `HEAD` rather than `<target>`, so landing with `--target <other>` leaves `draft/<slug>` behind (`branch_deleted: false`).
   - **Fix:** Replace `git branch -d` with `git -C mr update-ref -d refs/heads/<branch> <landed_tip>` (safe CAS delete after `<target>` already atomically advanced to `<landed_tip>`), and add a `--target <other>` fixture in `test/worktree.sh`.
2. **Deadlock-free merged verify capture + fail-closed `git_drifted_files` in `Release_io`** (`src/quest/release_io.ml`, `test/release-door.sh`) — *Small fix (2 files).*
   - **Evidence:** Cold grader `92400dbc` follow-ups #1–#3: (a) `verify_merged_tree` runs `make check-full` / `BP3_RELEASE_VERIFY_CMD` through `run_capture_both` (drains stdout before stderr, risking >64 KB stderr pipe deadlock); (b) `git_drifted_files` returns `[]` on git error, failing open to `Doc_only`; (c) `Makefile` `lint:` doc-only verify branch has no CI fixture yet.
   - **Fix:** Add `run_capture_merged` (stderr duped to stdout pipe) for `verify_merged_tree`, return `Error` / fail closed to `Release.Code` on `git_drifted_files` error, and add a `Makefile` `lint:` pass/fail fixture in `test/release-door.sh`.
3. **Thaw `docs/icebox/2026-11-24-grade-active-s-warden.md` (grade active_s in Warden)** — *Follow-up quest (promotion trigger fired twice).*
   - **Evidence:** `metrics:node-draft-1-draft-desk-cli:c1` (2887s external stall in `4db71e89`) is the second consecutive quest (after `sqlite-control-plane` `97b3b290`) producing major `grade_inversion` + `cycle_outlier` FPs from external sleep/offline/API gaps.
   - **Action:** Keep frozen or schedule as next small quest to add `grade.active_s` to `metrics_io.ml` and gate Warden rules on active time.

## Owner disposition

| # | Proposal | Disposition |
|---|---|---|
| 1 | CAS `update-ref -d` for non-HEAD `--target` in `worktree.ml` + `test/worktree.sh` | `applied 5bccd167` |
| 2 | Deadlock-free `run_capture_merged` + fail-closed `git_drifted_files` + `lint:` fixture in `release_io.ml` / `test/release-door.sh` | `applied 5bccd167` |
| 3 | Thaw `docs/icebox/2026-11-24-grade-active-s-warden.md` (`grade.active_s` in Warden) | `icebox docs/icebox/2026-11-24-grade-active-s-warden.md` (trigger fired 2x; ready to thaw as follow-up quest) |
