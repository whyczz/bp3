---
date: 2026-11-26
status: frozen
promoted: null
---

# Warden exploration quality middleware (`explore_quality`)

## Context
During `2026-11-23-dag-contracts` framing (2026-11-26), the owner settled that `Explore` nodes are bounded by `--max-iterations` (never live token caps) and that Warden should **not** police exploration token counts. Instead, Warden should act as post-hoc validation/middleware to improve future explorations by checking report quality, surfaced edge cases, and reusable lessons.

## Smallest workable shape
Add one Layer-1 Warden plug (`plug_explore_quality`) in `src/warden/warden.ml` (plus `Warden_io` evidence) that inspects every landed `--kind explore` node:
1. Confirms a `REPORT.md` exists under `docs/quests/<quest>/explores/<node>/` in the landed commit (refuses/flags `missing_explore_report`, `minor`).
2. Checks `REPORT.md` states the original `--target`, the measured outcome (`hit | missed | inconclusive`), and an Edge Cases / Lessons section.
3. Explicitly excludes `Explore` nodes from `context_bloat` or any future token-spend rule so explorations stay free to think deeply.

## Blockers
- Zero real `Explore` nodes have run in production quests yet — premature to guess what failure modes explorations actually hit in the wild.

## Promotion trigger
Promote to a quest once >= 3 real `--kind explore` nodes have landed across `bp3` or host repos and we have observed at least one recurring exploration report gap.
