---
status: frozen
date: 2026-11-25
promoted: null
---

# grade-active-seconds: gap-capped `grade.active_s` to prevent idle/stall false positives in Warden

## Context

During Warden audit of `2026-11-25-global-skills-and-backpack-toml`, `bp3 warden` reported two `major` Layer-1 findings on `node-manifest-1-backpack-toml-parser-and-config`:
- `cycle_outlier`: `3263s grade wall (> 300s)` (`metrics:node-manifest-1-backpack-toml-parser-and-config:c1`)
- `grade_inversion`: `grade 3564s vs author 563s (6.33x)` (`metrics:node-manifest-1-backpack-toml-parser-and-config`)

Inspecting the grader transcript (`c5250638-e59a-42a7-9f30-9bd9c400b2e9`) showed `step 20` -> `step 21` (`ERROR_MESSAGE`) had a single `+2471s` (~41 min) idle/API-stall gap (plus `+424s` at step 20), while total `tool_s` across 17 turns was only `190s` (~368s active). Because `bp3 q <quest> metrics scrape` already computes gap-capped `author.active_s` for authors (`src/quest/metrics_io.ml`) but only raw `grade.wall_s` for graders, any laptop sleep, approval wait, or API stall inflates `grade.wall_s` and trips both `cycle_outlier` and `grade_inversion` as false positives.

## Sketch

- Emit `grade.active_s` (using the same inter-step gap cap as `author.active_s`) alongside `grade.wall_s` in `src/quest/metrics_io.ml` and surface it in `src/quest/metrics.ml` rollups.
- Update `Warden.plug_cycle_outlier` and `Warden.plug_grade_inversion` (`src/warden/warden.ml`) to prefer `grade.active_s` when present (falling back to `grade.wall_s` for older `metrics.jsonl` records).
- Add unit tests in `test/unit/test_warden.ml` and `test/unit/test_metrics.ml` covering a grader transcript with a long idle gap vs a genuinely slow active grade.
- Deliberately do NOT change `grade.wall_s` semantics or rewrite historical `metrics.jsonl` files.

## Blockers

None known; touches > 2 files across `src/quest/` and `src/warden/` (belongs in a small quest rather than a post-land warden patch).

## Promotion trigger

Promote to a quest if `cycle_outlier` or `grade_inversion` fires another idle-gap false positive in the next 2–3 quests, or when batching the next `warden` / `metrics` polish quest.
