---
date: 2026-11-25
quest: QUEST.md
---

# Post-quest feedback & Warden audit — `2026-11-25-global-skills-and-backpack-toml`

## Human post-land feedback

- Ran unattended via `/induct-yolo` (5/5 nodes landed to `node_fin`, 6/6 verbatim cold grades, 0 parked nodes).
- Owner directed: run `/warden`, apply the proposals, promote/release, and present the overview.
- Rebased cleanly onto `master` (`ba2bd5db`, 6/6 commits, 0 conflicts) after parallel quest frames landed on `master`.

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-25-global-skills-and-backpack-toml` (pre-proposal baseline at `345f306e`):

- **Sessions scanned:** `7`
- **Counts:** `total: 3` (`by_layer: { git: 2, session: 1 }`; `by_rule: { cycle_outlier: 1, grade_inversion: 1, context_bloat: 1 }`)

| # | Rule | Layer | Severity | Node / Cycle | Observed | Threshold | Evidence ref | Audit (TP / FP & root cause) |
|---|---|---|---|---|---|---|---|---|
| 1 | `cycle_outlier` | `git` | `major` | `manifest.1` c1 | `3263s grade wall` | `> 300s grade wall` | `metrics:node-manifest-1-backpack-toml-parser-and-config:c1` | **FP (measurement gap):** inspecting `c5250638` transcript shows a single `+2471s` (~41m) external idle/API-stall gap at step 21 (`ERROR_MESSAGE`) + `+424s` at step 20; actual `tool_s` was `190s` (~368s active). |
| 2 | `grade_inversion` | `git` | `major` | `manifest.1` | `grade 3564s vs author 563s (6.33x)` | `> 180s & > 1.5x author` | `metrics:node-manifest-1-backpack-toml-parser-and-config` | **FP (same root cause as #1):** raw `grade.wall_s` included the 41m stall on c1 (`c2` was clean at `301s` wall / `86s` tool). |
| 3 | `context_bloat` | `session` | `minor` | `global.1` c1 | `490k tok (15 turns)` | `> 400k tok (agy)` | `tx:...09796efd.../transcript.jsonl#step:377` | **TP (expected before compaction):** single-session author hit 490k right at the end of node 3 (`global.1`), immediately before auto-compaction reset context for `global.2` and `skills.1` (both stayed well under 400k). |

## Proposals (`<= 3`)

1. **Isolate `agy_settings` under `BP3_GLOBAL_HOME` & clean stale `release-sync.sh` fixture** (`scripts/install-bp3.sh`, `test/release-sync.sh` — 2 files, deterministic fix):
   - Default `agy_settings` in `scripts/install-bp3.sh:76` to `${BP3_AGY_SETTINGS:-${BP3_GLOBAL_HOME:-$HOME}/.gemini/antigravity-cli/settings.json}` so isolated installs never touch real `$HOME`; drop stale section-2 auto-commit comment and unused failing `pre-commit` hook in `test/release-sync.sh`, and assert `BP3_GLOBAL_HOME` isolation.
2. **Retarget `Store.load_plan_file` onto `Gitx.current_root ()` & fuzz `option gate` in `Brief` law** (`src/quest/store.ml`, `test/unit/test_brief.ml` — 2 files, deterministic fix):
   - Replace startup `root` with `current_root ()` in `Store.load_plan_file` so retargeted `Gitx` callers never read a stale startup root; extend `law_is_verbatim_exact` in `test/unit/test_brief.ml` to fuzz `None` and `Some` `[grade].gate` commands.
3. **Add gap-capped `grade.active_s` to eliminate idle-stall false positives in Warden** (`src/quest/metrics_io.ml`, `src/quest/metrics.ml`, `src/warden/warden.ml` + unit tests — multi-file):
   - Root cause of findings #1 and #2 (`cycle_outlier` + `grade_inversion` on `c5250638` step 21 `+2471s` stall). Freeze to `docs/icebox/2026-11-25-grade-active-seconds.md` for a future small quest.

*(Pruning check: zero prose files added/edited in proposals 1–3; all fixes are deterministic code/test/icebox.)*

## Owner disposition

Owner instruction (`2026-11-25`): *"run the warden, apply the proposals, then give the overbrew of what we did"* + *"and then let's promote this"*.

| Proposal | Disposition | Reference |
|---|---|---|
| 1. `BP3_GLOBAL_HOME` isolation in `install-bp3.sh` + `test/release-sync.sh` cleanup | `applied` | `c6ed4911` |
| 2. `Store.load_plan_file` `current_root ()` + `test_brief.ml` gate fuzzing | `applied` | `c6ed4911` |
| 3. Gap-capped `grade.active_s` for Warden plugs | `icebox` | `docs/icebox/2026-11-25-grade-active-seconds.md` (`c6ed4911`) |
