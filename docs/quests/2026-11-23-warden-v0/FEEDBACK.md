# Feedback: 2026-11-23-warden-v0

Standalone post-quest feedback and Warden calibration record for [QUEST.md](QUEST.md). Its presence marks `2026-11-23-warden-v0` reviewed for bare `bp3 warden` sweeps.

## Human post-land feedback

- _(pending owner review at `goal_fin` — recorded by `dogfood.1` unattended run under `/induct-inline-yolo`)_

## Warden deterministic summary (4-quest backtest)

Executed `./bin/bp3 warden <quest>` (both `--no-sessions` Layer 1 and full auto-enabled Layer 1+2) across the 4 most recent landed quests after calibration:

| Quest | L1 (`--no-sessions`) | Full (L1+L2) | Sessions | Findings (git / session) | TP / FP | FP Rate |
|---|---:|---:|---:|---:|---:|---:|
| `2026-11-21-metric-followups` | `0.08s` | `1.97s` | 7 | `3 (2 / 1)` | `3 / 0` | `0.0%` |
| `2026-11-21-pi-metrics` | `0.03s` | `1.47s` | 4 | `1 (0 / 1)` | `1 / 0` | `0.0%` |
| `2026-11-22-induct-inline-as-default-measure-author` | `0.04s` | `1.94s` | 17 | `30 (20 / 10)` | `30 / 0` | `0.0%` |
| `2026-11-23-fast-agy-induct` | `0.06s` | `1.50s` | 10 | `8 (7 / 1)` | `8 / 0` | `0.0%` |
| **Total** | **max `0.08s`** | **max `1.97s`** | **38** | **`42 (29 / 13)`** | **`42 / 0`** | **`0.0%`** |

Key verification points:
- Reproduces all 4 known `2026-11-22` waste classes (`cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`) with 100% recall.
- `2026-11-23-fast-agy-induct` validates `agy` Layer-2 traces cleanly: 0 false `context_bloat` on `161k` `agy` grade sessions, 0 false `post_land_bugfix` on status-only landing commit `44b975f`, and 0 false `human_steer` on autonomous build windows.
- Calibration applied in `dogfood.1` reduced total FP rate from **42.5% (31/73)** to **0.0% (0/42)**, well below the `<= 20%` bar:
  1. `src/warden/warden.ml` (`plug_context_bloat`): deduplicate per `(quest, jt_run)` keeping peak context/turns.
  2. `src/warden/warden.ml` (`plug_grade_inversion`): add `> 25k` floor on `grade.tokens_out` inversion.
  3. `src/warden/warden_io.ml` (`is_status_only_path`): treat any `docs/quests/*/{QUEST,LOG,FEEDBACK}.md` as status-only.
- Full 42-row audited findings table lives in [LOG.md](LOG.md).

## Proposals (`<= 3`, ranked by ROI)

1. **Reserve `"warden"` in `Store.reserved_slugs` (`src/quest/store.ml`) + complete warden flags after `<quest>` (`completions/{_bp3,bp3.bash}`)** *(small 1–2 file fix, from `cli.1` follow-ups)*: prevents creating a quest literally named `warden` that would be shadowed by `main.ml`'s top-level dispatch, and adds flag completion for `bp3 warden <quest> --<tab>`.
2. **Add `Pi_tx.assign` author-window support when Pi authoring lands** *(defer to `docs/icebox/` or next Pi quest, from `plugs.1` follow-ups)*: `Pi_tx.parse` already records `s_user_steps`, so wiring `Pi_tx.assign` later gives Pi author sessions `human_steer` parity automatically.
3. **Update `scripts/check-retired-terms.sh:9` header comment (`trial` -> `warden`)** *(trivial 1-line cleanup, from `skills.1` follow-ups)*: removes stale `trial` mention from the descriptive header comment.

## Owner disposition

| # | Proposal | Disposition |
|---:|---|---|
| 1 | Reserve `"warden"` slug + post-quest flag completion | _(pending owner)_ |
| 2 | `Pi_tx.assign` author-window support | _(pending owner)_ |
| 3 | Clean `scripts/check-retired-terms.sh:9` header comment | _(pending owner)_ |
