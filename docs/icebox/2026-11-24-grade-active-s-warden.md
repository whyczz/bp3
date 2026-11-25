---
status: frozen
date: 2026-11-24
promoted: null
---

# grade-active-s-warden: idle-gap-clamped grade.active_s so Warden ignores sleep/outage stalls

## Context

During `/warden 2026-11-23-sqlite-control-plane` (`docs/quests/2026-11-23-sqlite-control-plane/FEEDBACK.md`), `bp3 warden` emitted two `major` findings on `node-repo-1-repo-registry` cycle 2:
- `cycle_outlier`: `2234s grade wall (> 300s)` (`metrics:node-repo-1-repo-registry:c2`)
- `grade_inversion`: `grade 2401s vs author 502s (4.78x)` (`metrics:node-repo-1-repo-registry`)

Inspecting grader transcript `97b3b290-5c4c-4d38-a11a-da6a6d3e27f5` showed the grader only ran for ~182s active (`grade.tool_s = 123s`): `02:03:20Z -> 02:05:44Z` (144s), followed by a 2048s external stall until `02:39:52Z` (`ERROR_MESSAGE`), then `02:39:56Z -> 02:40:34Z` (38s). Author cycles already record gap-clamped `author.active_s` in `metrics.jsonl`, whereas grade cycles only record raw `grade.wall_s` and `grade.tool_s`.

Owner context (2026-11-24): normal single-MacBook workflow includes closing the laptop lid while commuting or dropping internet mid-run, so wall-clock stalls from sleep/offline gaps are expected and shouldn't page Warden as major grading regressions.

## Sketch

- Compute idle-gap-clamped `grade.active_s` alongside `grade.wall_s` in `src/quest/metrics.ml` / `src/quest/agy_tx.ml` / `src/quest/pi_tx.ml` / Claude scraper using the same gap-clamping rule as `author.active_s`, and include `grade_active_s` in `metrics r` rollups.
- Update `src/warden/warden.ml` so `cycle_outlier` and `grade_inversion` evaluate `grade.active_s` when present (falling back to `grade.wall_s` on legacy samples) and optionally emit a distinct `minor` / informational note when `wall_s - active_s` indicates an external stall (`ERROR_MESSAGE` / laptop sleep).
- Deliberately out of scope: modifying historical `metrics.jsonl` records or adding new threshold flags unless needed.

## Blockers

- Decide the exact idle-gap cap for graders (e.g. same threshold as `author.active_s` vs a grader-specific cap so long legitimate `make check-full` runs of 60–120s are never clamped).
- Confirm backward compatibility with existing `metrics.jsonl` samples across Claude, pi, and agy parsers (`test_metrics.ml`, `test_warden.ml`).

## Promotion trigger

Thaw when another quest hits a `cycle_outlier` or `grade_inversion` false positive from laptop sleep / model timeout during `/warden`, or when next modifying `src/warden/` or `src/quest/metrics.ml`.
