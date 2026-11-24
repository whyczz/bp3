---
date: 2026-11-23
quest: ../../QUEST.md
node: dogfood.1
status: proposed
---

# dogfood.1 - backtest-recent-quests: calibrate Warden thresholds on 4 real landed quests

## TL;DR

Run `bp3 warden <quest>` across the 4 most recent landed quests (`2026-11-21-metric-followups`, `2026-11-21-pi-metrics`, `2026-11-22-induct-inline-as-default-measure-author`, `2026-11-23-fast-agy-induct`), classify every finding (Layer 1 + Layer 2, including `human_steer` and `post_land_bugfix`) as true-positive vs false-positive in `docs/quests/2026-11-23-warden-v0/LOG.md` and `FEEDBACK.md`, and tune any plug whose false-positive rate pushes the total above 20%.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 warden --all
usage: bp3 init ...
```

Design trace:

```text
$ ./bin/bp3 warden <q>   (for each of the 4 most recent landed quests)
  - every finding (Layer 1 git/repo + Layer 2 auto-enabled session traces) audited and labeled TP or FP in LOG.md + FEEDBACK.md
  - 2026-11-22 reproduces cycle_outlier, minor_only_bounce, vacuous_test_bounce, grade_inversion
  - 2026-11-23-fast-agy-induct validates agy Layer-2 traces (0 false context_bloat on 161k agy run, accurate human_steer & post_land_bugfix)
  - total FP rate <= 20% across both layers (if > 20%, tighten threshold in src/warden/warden.ml + test_warden.ml and re-run)
  - `--no-sessions` Layer-1 wall time < 1s per quest; full auto-enabled Layer 1+2 wall time recorded in LOG.md
```

```yaml
objective: prove Warden's signal-to-noise ratio (including human_steer and post_land_bugfix) on 4 real landed quests before promoting warden-v0
prove by:
  - exact command outputs of bp3 warden <q> on the 4 recent landed quests recorded in LOG.md + FEEDBACK.md
  - precision/FP table showing FP <= 20% and <1s Layer-1 latency
  - make check-full
done when: LOG.md and FEEDBACK.md carry the audited 4-quest backtest table with FP <= 20% and make check-full passes
```

## Diagram

```text
4 landed quests (metric-followups, pi-metrics, induct-inline-as-default, fast-agy-induct)
   │
   ▼
bp3 warden <q> ──► label each finding TP / FP ──► FP > 20%? ──► tune plug in src/warden/warden.ml + re-test
                                                     │ no
                                                     ▼
                                       record audit table in LOG.md + FEEDBACK.md
```

## Pseudocode

```python
QUESTS = [
    "2026-11-21-metric-followups",
    "2026-11-21-pi-metrics",
    "2026-11-22-induct-inline-as-default-measure-author",
    "2026-11-23-fast-agy-induct",
]
results = [bp3_json(f"warden {q}") for q in QUESTS]
# Audit every finding by hand against its evidence_ref -> compute TP / (TP + FP) <= 20% FP
```

## Tables

| Field | Value |
|---|---|
| Intent | calibrate all 12 plug thresholds on real evidence (Claude, Pi, and `agy` runs) so Warden stays high-signal |
| Lane | micro |
| Output | `docs/quests/2026-11-23-warden-v0/LOG.md`, `docs/quests/2026-11-23-warden-v0/FEEDBACK.md` (new), plus optional threshold tweak in `src/warden/warden.ml` + `test/unit/test_warden.ml` if FP > 20% |
| Acceptance | fails today (no `bp3 warden` door); passes when audited 4-quest table is recorded with FP <= 20% and `make check-full` passes |
| Depends on | `skills.1 - warden-skill` |
| Must not touch | `skills/*`, `bin/bp3`, `CONSTRAINTS.md` |

## Prose

- Directly closes both `ICEBOX.md`'s false-positive budget blocker and the closing red chair's `human_steer` precision check on real `agy` + Claude + Pi transcripts.
- **Test split:** True end-to-end live backtest across 4 real landed quests; property-based tests omitted (stated decision: calibration run over real repo history).
