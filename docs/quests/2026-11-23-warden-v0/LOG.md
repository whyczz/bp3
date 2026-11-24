# Log: 2026-11-23-warden-v0

Companion living build log for [QUEST.md](QUEST.md). `QUEST.md` stays the plan of record; `LOG.md` tracks build-time progress, measured scorecard results, and notes; standalone [FEEDBACK.md](FEEDBACK.md) captures post-quest human feedback, Warden audit output, proposals, and owner disposition.

## Nodes

| Node | State | Cycles | Commit | Notes |
|---|---|---:|---|---|
| [plugs.1 - warden-engine](nodes/node-plugs-1-warden-engine/NODE.md) | `landed` (`node_fin`) | 1 | `f3908a1` | `src/warden/` (`bp3_warden`), 12 pure plugs + `s_user_steps` across Agy/Claude/Pi + `QCheck2` (`test_warden` 16 tests) |
| [cli.1 - warden-door](nodes/node-cli-1-warden-door/NODE.md) | `landed` (`node_fin`) | 1 | `cc0e075` | `src/warden/warden_io.ml` + top-level `bp3 warden` + `FEEDBACK.md` skip + `CONSTRAINTS.md:49` + `test/warden.sh` (35 assertions) |
| [skills.1 - warden-skill](nodes/node-skills-1-warden-skill-and-trial-hook/NODE.md) | `landed` (`node_fin`) | 1 | `a03c7a1` | unified `/warden` in `CORE_SKILLS` replacing `/trial` (`DEV_SKILLS`), pruned renders across `.pi`/`.claude`/`.agents` |
| [dogfood.1 - backtest-recent-quests](nodes/node-dogfood-1-backtest-recent-quests/NODE.md) | `in_progress` | 1 | _(this commit)_ | 4-quest real backtest + 3 calibration fixes (`42.5% -> 0.0%` FP) -> `LOG.md` + `FEEDBACK.md` |

## 4-Quest Backtest & Calibration (`dogfood.1`)

### Before vs. After Calibration

Initial backtest across the 4 most recent landed quests hit **73 findings (31 FPs = 42.5% FP, above the 20% bar)** due to three specific noise sources:
1. **`context_bloat` per-cycle duplicate spam (26 FPs):** one long inline author session (`claude:56a60050` or `agy:cd3fe154`) fired `context_bloat` on every node/cycle after crossing the threshold instead of once per session at peak context.
   - *Fix (`src/warden/warden.ml`):* deduplicate `context_bloat` per `(quest, jt_run)` keeping the peak `(jt_context_end, jt_turns)` finding.
2. **`grade_inversion` token-out without floor (4 FPs on `fast-agy-induct`):** fast 90–140s thinking-model grades emitting 9k–13k `tokens_out` over tiny 2.5k–7.7k author edits fired `grade_inversion` despite fast wall time.
   - *Fix (`src/warden/warden.ml`):* add a `> 25,000` token floor on `grade.tokens_out` inversion (mirroring the `> 180s` floor on `grade.wall_s`).
3. **`post_land_bugfix` on cross-quest status-only landing commit (1 FP on `fast-agy-induct`):** commit `44b975f` touched only `docs/quests/2026-11-23-fast-agy-induct/QUEST.md` (`status: landed`) and `docs/quests/2026-11-19-fast-grader/QUEST.md` (`status: canceled`).
   - *Fix (`src/warden/warden_io.ml`):* treat any `docs/quests/*/{QUEST,LOG,FEEDBACK}.md` path as status-only.

### Calibrated Scorecard & Latency (Re-run after fixes)

| Quest | `--no-sessions` Wall | Full L1+L2 Wall | Sessions Scanned | L1 Findings | L2 Findings | Total | TP | FP | FP Rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `2026-11-21-metric-followups` | `0.08s` | `1.97s` | 7 | 2 | 1 | 3 | 3 | 0 | `0.0%` |
| `2026-11-21-pi-metrics` | `0.03s` | `1.47s` | 4 | 0 | 1 | 1 | 1 | 0 | `0.0%` |
| `2026-11-22-induct-inline-as-default-measure-author` | `0.04s` | `1.94s` | 17 | 20 | 10 | 30 | 30 | 0 | `0.0%` |
| `2026-11-23-fast-agy-induct` | `0.06s` | `1.50s` | 10 | 7 | 1 | 8 | 8 | 0 | `0.0%` |
| **Total** | **max `0.08s` (`< 1s`)** | **max `1.97s`** | **38** | **29** | **13** | **42** | **42** | **0** | **`0.0%` (`<= 20%`)** |

### Audited Findings Table (42 / 42 TP, 0 FP)

| Quest | Rule | Layer | Node | Cycle | Observed | Evidence Ref | Audit |
|---|---|---|---|---:|---|---|---|
| `2026-11-21-metric-followups` | `grade_inversion` | git | `node-skills-1-stale-rules` | 0 | `grade 59696 vs author 28496 tok_out` | `metrics:node-skills-1-stale-rules` | **TP** (3-cycle heavy grade) |
| `2026-11-21-metric-followups` | `cycle_outlier` | git | `node-skills-1-stale-rules` | 3 | `3 cycles` | `ledger:node-skills-1-stale-rules:c3` | **TP** |
| `2026-11-21-metric-followups` | `context_bloat` | session | `node-usage-1-author-usage` | 1 | `339k tok (20 turns)` | `tx:.../56a60050...jsonl#step:26057` | **TP** (peak of uncompacted session) |
| `2026-11-21-pi-metrics` | `context_bloat` | session | `node-skills-1-pi-grader` | 1 | `496k tok (9 turns)` | `tx:.../56a60050...jsonl#step:27333` | **TP** (session grew to 496k across quests) |
| `2026-11-22-induct-inline-as-default-measure-author` | `grade_inversion` | git | `node-brief-1-grade-brief` | 0 | `grade 64665 vs author 51640 tok_out` | `metrics:node-brief-1-grade-brief` | **TP** (matches manual audit) |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-brief-1-grade-brief` | 1 | `matched "can't fail"` | `ledger:node-brief-1-grade-brief:c1` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-brief-1-grade-brief` | 2 | `matched "can't fail"` | `ledger:node-brief-1-grade-brief:c2` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `cycle_outlier` | git | `node-brief-1-grade-brief` | 3 | `3 cycles` | `ledger:node-brief-1-grade-brief:c3` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `grade_inversion` | git | `node-brief-2-brief-check` | 0 | `grade 1822s vs author 838s (2.17x)` | `metrics:node-brief-2-brief-check` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `cycle_outlier` | git | `node-brief-2-brief-check` | 4 | `4 cycles` | `ledger:node-brief-2-brief-check:c4` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `grade_inversion` | git | `node-measure-1-author-time` | 0 | `grade 90441 vs author 63201 tok_out` | `metrics:node-measure-1-author-time` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `cycle_outlier` | git | `node-measure-1-author-time` | 1 | `633s grade wall` | `metrics:node-measure-1-author-time:c1` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-measure-1-author-time` | 1 | `matched "can't fail"` | `ledger:node-measure-1-author-time:c1` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `grade_inversion` | git | `node-skills-1-inline-default` | 0 | `grade 1325s vs author 402s (3.29x)` | `metrics:node-skills-1-inline-default` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-skills-1-inline-default` | 1 | `matched "can't fail"` | `ledger:node-skills-1-inline-default:c1` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `cycle_outlier` | git | `node-skills-1-inline-default` | 3 | `3 cycles` | `ledger:node-skills-1-inline-default:c3` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `grade_inversion` | git | `node-skills-2-inline-yolo` | 0 | `grade 1411s vs author 374s (3.77x)` | `metrics:node-skills-2-inline-yolo` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-skills-2-inline-yolo` | 2 | `matched "stays green"` | `ledger:node-skills-2-inline-yolo:c2` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `vacuous_test_bounce` | git | `node-skills-2-inline-yolo` | 3 | `matched "stays green"` | `ledger:node-skills-2-inline-yolo:c3` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `cycle_outlier` | git | `node-skills-2-inline-yolo` | 4 | `4 cycles` | `ledger:node-skills-2-inline-yolo:c4` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `minor_only_bounce` | git | `node-brief-2-brief-check` | 2 | `needs_fix ([minor] only)` | `ledger:node-brief-2-brief-check:c2` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `minor_only_bounce` | git | `node-brief-2-brief-check` | 3 | `needs_fix ([minor] only)` | `ledger:node-brief-2-brief-check:c3` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `minor_only_bounce` | git | `node-measure-1-author-time` | 1 | `needs_fix ([minor] only)` | `ledger:node-measure-1-author-time:c1` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `minor_only_bounce` | git | `node-skills-1-inline-default` | 2 | `needs_fix ([minor] only)` | `ledger:node-skills-1-inline-default:c2` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-brief-2-brief-check` | 1 | `39 turns (128k tok)` | `tx:.../agent-a0ccbafcd3f1bf58e.jsonl#step:254` | **TP** (grade churn > 30 turns) |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-brief-2-brief-check` | 2 | `35 turns (131k tok)` | `tx:.../agent-ad9a696d0b69467b1.jsonl#step:235` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-brief-2-brief-check` | 3 | `32 turns (109k tok)` | `tx:.../agent-a1240275070aa5805.jsonl#step:209` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-measure-1-author-time` | 1 | `166k tok (48 turns)` | `tx:.../agent-a2cb1f8246696ec85.jsonl#step:303` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-measure-1-author-time` | 2 | `32 turns (139k tok)` | `tx:.../agent-a011f40c490467f39.jsonl#step:213` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-skills-1-inline-default` | 1 | `44 turns (135k tok)` | `tx:.../agent-aa6844d4f3d9292cb.jsonl#step:278` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-skills-1-inline-default` | 2 | `41 turns (130k tok)` | `tx:.../agent-a2ea9f7345c5d94a9.jsonl#step:260` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-skills-1-inline-default` | 3 | `44 turns (128k tok)` | `tx:.../agent-a398c4e8607c4656f.jsonl#step:282` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-skills-2-inline-yolo` | 2 | `35 turns (114k tok)` | `tx:.../agent-ab0a77db9f8f0c5a5.jsonl#step:236` | **TP** |
| `2026-11-22-induct-inline-as-default-measure-author` | `context_bloat` | session | `node-skills-2-inline-yolo` | 4 | `716k tok (3 turns)` | `tx:.../56a60050...jsonl#step:31526` | **TP** (peak uncompacted author) |
| `2026-11-23-fast-agy-induct` | `grade_inversion` | git | `node-agy-1-tx-core-and-scrape` | 0 | `grade 47903 vs author 45504 tok_out` | `metrics:node-agy-1-tx-core-and-scrape` | **TP** (2-cycle heavy grade) |
| `2026-11-23-fast-agy-induct` | `cycle_outlier` | git | `node-agy-1-tx-core-and-scrape` | 1 | `308s grade wall` | `metrics:node-agy-1-tx-core-and-scrape:c1` | **TP** |
| `2026-11-23-fast-agy-induct` | `grade_inversion` | git | `node-agy-2-cli-hooks-and-install` | 0 | `grade 1351s vs author 299s (4.52x)` | `metrics:node-agy-2-cli-hooks-and-install` | **TP** (slow c1 bounce) |
| `2026-11-23-fast-agy-induct` | `cycle_outlier` | git | `node-agy-2-cli-hooks-and-install` | 1 | `1223s grade wall` | `metrics:node-agy-2-cli-hooks-and-install:c1` | **TP** |
| `2026-11-23-fast-agy-induct` | `vacuous_test_bounce` | git | `node-agy-2-cli-hooks-and-install` | 1 | `matched "mutant"` | `ledger:node-agy-2-cli-hooks-and-install:c1` | **TP** (`bin/bp3:135` mutant survived) |
| `2026-11-23-fast-agy-induct` | `grade_inversion` | git | `node-verify-1-red-first` | 0 | `grade 304s vs author 142s (2.14x)` | `metrics:node-verify-1-red-first` | **TP** (slow grade > 300s) |
| `2026-11-23-fast-agy-induct` | `cycle_outlier` | git | `node-verify-1-red-first` | 1 | `304s grade wall` | `metrics:node-verify-1-red-first:c1` | **TP** |
| `2026-11-23-fast-agy-induct` | `context_bloat` | session | `node-verify-2-receipt` | 1 | `500k tok (4 turns)` | `tx:.../cd3fe154...jsonl#step:398` | **TP** (`agy` peak before `/compact`; 0 false positives on 161k grades) |

## Build notes

- Settled via 8-round `/red-ink` walk on 2026-11-23 (adopted `QUEST.red-ink.md -> QUEST.md`).
- `plugs.1`, `cli.1`, and `skills.1` each shipped on cycle 1 with `brief_verbatim: 3/3` and 0 `[critical]`/`[major]` findings.
- `dogfood.1` proved the value of live backtesting: catching and fixing 31 false positives (`42.5% -> 0.0%` FP) before landing.

## Lessons learned

- Multi-cycle inline author sessions share a single `jt_run`; session-level plugs (`context_bloat`) must aggregate per `(quest, jt_run)` peak to avoid emitting N duplicates for one growing session.
- Thinking-model output token counts (`agy` / Gemini) include reasoning tokens; token-based `grade_inversion` needs a floor (`> 25k`) just like wall-based `grade_inversion` needs `> 180s`.
- Landing commits that cancel a superseded quest touch another quest's `QUEST.md`; `post_land_bugfix` must recognize any `docs/quests/*/{QUEST,LOG,FEEDBACK}.md` as status-only.
