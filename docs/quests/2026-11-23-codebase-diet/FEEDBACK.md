# 2026-11-23-codebase-diet — Post-Quest Feedback & Warden Audit

## Human post-land feedback

- Owner (2026-11-25): instructed "warden this. apply fixes. then promote" after the unattended 5/5 Cycle-1 `induct-inline-yolo` run (`rollup: landed`, `fin: goal_fin`, net `-13,892` LOC across 108 files).
- Live operational friction observed during `skills.1` authoring: default `bp3 harness desk prepare <q> <n>` still nests grade desks under `.bp3/worktrees/<q>/<n>/...` (inside the quest desk), causing `git add -A` to stage a gitlink `160000` and `./scripts/receipt` to see a dirty worktree during overlapping work; reinforces prioritizing `docs/icebox/2026-11-24-central-desks-dir.md` next.

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-23-codebase-diet --format json`

- `sessions_scanned`: `6`
- `by_layer`: `git: 1`, `session: 1`
- `by_rule`: `grade_inversion: 1`, `context_bloat: 1`
- `total`: `2`

| # | Rule | Layer | Sev | Node | Cycle | Observed | Threshold | Evidence ref | Audit |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `grade_inversion` | `git` | `major` | `node-retire-2-slim-harness-to-desk` | - | `grade 33357 vs author 26127 tok_out` | `> 25k & grade.tokens_out > author.tokens_out` | `metrics:node-retire-2-slim-harness-to-desk` | **TP (deletion-heavy diff)** — `retire.2` deleted 4,663 LOC (`src/quest/harness.ml` + 7 suites) with only +125 LOC added; author output tokens stay low on deletions while the `high-blast-radius` `pro` grader spent reasoning tokens auditing all 28 touched files |
| 2 | `context_bloat` | `session` | `minor` | `node-clean-2-names-and-desk-hygiene` | c1 | `499k tok (10 turns)` | `> 400k tok (agy)` | `tx:/Users/whycz/.gemini/antigravity-cli/brain/661e5fe6-6755-40e1-9f05-f4b4cab29c4a/.system_generated/logs/transcript.jsonl#step:480` | **TP** — single uncompacted session carried triage + full 5-round `/red-ink` + all 5 inline nodes before auto-compaction |

## Proposals (`<= 3`, ranked by ROI)

| # | ROI | Scope | Proposal | Target file(s) | Grounding / Evidence | Pruning check |
|---|---|---|---|---|---|---|
| 1 | High | Small (3 files) | Add `RETIRED_SKILLS` filtering to `bin/bp3` `skills_install --harness=pi` so upgrading downstream repos automatically removes stale `induct-inline*`/`bp3g*`/`traverse*` exclusions from `.pi/settings.json` (preserving unrelated entries), with regression coverage in `test/skills.sh` and `RETIRED_SKILLS=` exemption in `scripts/check-retired-terms.sh`. | `bin/bp3`, `scripts/check-retired-terms.sh`, `test/skills.sh` | `git:6672194` (`skills.1` c1 cold grader follow-up) | Code + test only; pruned stale workflow comment in `bin/bp3:325-326` |
| 2 | Med | Small (6 files) | Validate `'0'..'9'` digits in `Util.epoch_of_iso` (+ unit tests), replace `hooks.ml:save_registry`'s hand-rolled `.tmp` writer with `Util.write_file_atomic`, and scrub dead Node / `test/pi-discovery.mjs` / JS `unit`-tier comments from `readme.md`, `test/suites.tsv`, and `scripts/check-changed.sh`. | `src/quest/util.ml`, `src/quest/hooks.ml`, `test/unit/test_util.ml`, `readme.md`, `test/suites.tsv`, `scripts/check-changed.sh` | `git:eb514fe` & `git:4e330e9` (`clean.1` & `retire.1` cold grader follow-ups) | Deleted 10 stale doc/comment lines (`readme.md` Node & `pi-discovery.mjs` block) |
| 3 | High | Larger (icebox) | Move all quest and grade desks out of repo-nested `.bp3/worktrees/` into unified `~/.bp3/desks/` (eliminating grade-desk gitlink collisions and the `Makefile` `--root=.` dune hack); operationally start `/induct-yolo` in a fresh or compacted session after `/red-ink` to stay under the 400k `context_bloat` limit. | `docs/icebox/2026-11-24-central-desks-dir.md` | Live `skills.1` grade-desk nesting collision + `bp3 warden` finding #2 (`tx:...#step:480`, 499k tok) | Already frozen in `docs/icebox/`; 0 prose added to skills |

## Owner disposition

| # | Proposal | Disposition |
|---|---|---|
| 1 | Prune retired bp3 skill exclusions from `.pi/settings.json` on `skills install` | `applied 05d1e1b` |
| 2 | `Util.epoch_of_iso` digit check, `hooks.ml` atomic write dedup, scrub dead Node docs | `applied 05d1e1b` |
| 3 | Unified `~/.bp3/desks/` central desk root (next quest) | `icebox docs/icebox/2026-11-24-central-desks-dir.md` |
