# 2026-11-23-sqlite-control-plane — Post-Quest Feedback & Warden Audit

## Human post-land feedback

- Owner (2026-11-24): approved all 3 proposals; noted for Proposal #3 that single-MacBook commuting (closing laptop lid / dropping internet mid-run) naturally causes wall-clock gaps that shouldn't fire major Warden regressions.

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-23-sqlite-control-plane`

- `sessions_scanned`: `7`
- `by_layer`: `git: 2`, `session: 1`
- `by_rule`: `grade_inversion: 1`, `cycle_outlier: 1`, `context_bloat: 1`
- `total`: `3`

| # | Rule | Layer | Sev | Node | Cycle | Observed | Threshold | Evidence ref | Audit |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `grade_inversion` | `git` | `major` | `node-repo-1-repo-registry` | - | `grade 2401s vs author 502s (4.78x)` | `> 180s & > 1.5x author` | `metrics:node-repo-1-repo-registry` | **FP (external stall)** — driven entirely by finding #2 (`2048s` idle/outage gap inside `97b3b290`); active grade wall across c1+c2 was ~350s vs author 502s (`0.70x`) |
| 2 | `cycle_outlier` | `git` | `major` | `node-repo-1-repo-registry` | c2 | `2234s grade wall` | `> 300s grade wall` | `metrics:node-repo-1-repo-registry:c2` | **FP (external stall)** — grader transcript `97b3b290` ran `02:03:20Z -> 02:05:44Z` (144s), stalled `2048s` until `02:39:52Z` (`ERROR_MESSAGE`), then finished at `02:40:34Z` (38s); `grade.tool_s = 123s`, ~182s active |
| 3 | `context_bloat` | `session` | `minor` | `node-repo-1-repo-registry` | c2 | `495k tok (4 turns)` | `> 400k tok (agy)` | `tx:/Users/whycz/.gemini/antigravity-cli/brain/31a4f5cb-15ea-4a18-b348-12b31d9d0b01/.system_generated/logs/transcript.jsonl#step:398` | **TP** — continuous session carried `/red-ink` + `db.1` + `repo.1` c1/c2 before auto-compaction prior to `compat.1` |

## Proposals (`<= 3`, ranked by ROI)

| # | ROI | Scope | Proposal | Target file(s) | Grounding / Evidence | Pruning check |
|---|---|---|---|---|---|---|
| 1 | High | Small (1 file) | Default `export BP3_COMPLETIONS_DIR="${BP3_COMPLETIONS_DIR:-$work/completions}"` at the top of `test/skills.sh` (matching `test/mode.sh:18`) so standalone `./test/skills.sh` runs never touch the owner's global zsh completions. | `test/skills.sh` | `compat.1` c1 cold grader `FOLLOW-UPS #1` | Test-only guard; 0 prose added |
| 2 | Med | Small (2 files) | Check `(None, find_by_path_in db root_path)` before running `Db.slugify` in `Repo_store.add`, so an already-registered aliased repo whose directory basename has no alphanumerics still refreshes `last_seen_at` cleanly on `bp3 init`. | `src/repo/repo_store.ml`, `test/unit/test_repo.ml` | `repo.1` c2 cold grader `FOLLOW-UPS #1` | Code + unit test only; 0 prose added |
| 3 | Med | Larger (icebox) | Compute idle-gap-clamped `grade.active_s` (matching `author.active_s`) in `metrics` and have `bp3 warden`'s `cycle_outlier` / `grade_inversion` evaluate active time (or label sleep/error stalls separately) so laptop sleep or provider timeouts stop producing major false positives. | `src/quest/metrics.ml`, `src/warden/warden.ml` | `bp3 warden` findings #1–2 (`metrics:node-repo-1-repo-registry:c2`, `97b3b290` `02:05:44Z -> 02:39:52Z` `ERROR_MESSAGE` stall) | Code-only metric/rule improvement; 0 prose added |

## Owner disposition

| # | Proposal | Disposition |
|---|---|---|
| 1 | Global `BP3_COMPLETIONS_DIR` default in `test/skills.sh` | `applied 8636030` |
| 2 | Check existing `root_path` before `Db.slugify` in `Repo_store.add` | `applied 8636030` |
| 3 | Idle-gap-clamped `grade.active_s` for `bp3 warden` (`cycle_outlier` / `grade_inversion`) | `icebox docs/icebox/2026-11-24-grade-active-s-warden.md` |
