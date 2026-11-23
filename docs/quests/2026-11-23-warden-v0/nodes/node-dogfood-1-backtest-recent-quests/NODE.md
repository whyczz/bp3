---
date: 2026-11-23
quest: ../../QUEST.md
node: dogfood.1
status: proposed
---

# dogfood.1 - backtest-recent-quests: calibrate Warden thresholds on 4 real landed quests

## TL;DR

Run `bp3 q <quest> warden` across the 4 recent landed quests (`2026-11-21-metric-collectors`, `2026-11-21-metric-followups`, `2026-11-21-pi-metrics`, `2026-11-22-induct-inline-as-default-measure-author`), classify every finding as true-positive vs false-positive in `QUEST.md` build notes, and tune any plug whose false-positive rate pushes the total above 20%.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 q warden --all-landed
{"ok":false,"error":{"code":"E_USAGE",...}}
```

Design trace:

```text
$ ./bin/bp3 q <q> warden   (for each of the 4 landed quests)
  - every finding (Layer 1 git + Layer 2 auto-enabled session traces) audited and labeled TP or FP in QUEST.md ## Build notes
  - 2026-11-22 reproduces cycle_outlier, minor_only_bounce, vacuous_test_bounce, grade_inversion, plus any real Layer-2 retry/bloat/full-gate findings from local Claude/Pi/`agy` transcripts
  - total FP rate <= 20% across both layers (if > 20%, tighten threshold in src/quest/warden.ml + unit test and re-run)
  - `--no-sessions` Layer-1 wall time < 1s per quest; full auto-enabled Layer 1+2 wall time recorded in build notes
```

```yaml
objective: prove Warden's signal-to-noise ratio on real historical quests before declaring warden-v0 done
prove by:
  - exact command outputs of bp3 q <q> warden on the 4 recent landed quests recorded in QUEST.md build notes
  - precision/FP table showing FP <= 20%
  - make check-full
done when: QUEST.md build notes carry the audited 4-quest backtest table with FP <= 20% and make check-full passes
```

## Diagram

```text
4 landed quests (metric-collectors, metric-followups, pi-metrics, induct-inline-as-default)
   │
   ▼
bp3 q <q> warden ──► label each finding TP / FP ──► FP > 20%? ──► tune plug + re-test
                                                       │ no
                                                       ▼
                                         record audit table in QUEST.md
```

## Pseudocode

```python
QUESTS = [
    "2026-11-21-metric-collectors",
    "2026-11-21-metric-followups",
    "2026-11-21-pi-metrics",
    "2026-11-22-induct-inline-as-default-measure-author",
]
results = [bp3_json(f"q {q} warden") for q in QUESTS]
# Audit every finding by hand against its evidence_ref -> compute TP / (TP + FP)
```

## Tables

| Field | Value |
|---|---|
| Intent | calibrate thresholds on real evidence so Warden stays high-signal and never trains the owner to ignore it |
| Lane | micro |
| Output | `docs/quests/2026-11-23-warden-v0/QUEST.md` (`## Build notes` backtest table), plus optional threshold tweak in `src/quest/warden.ml` + `test/unit/test_warden.ml` if FP > 20% |
| Acceptance | fails today (no `warden` verb); passes when backtest table is recorded with FP <= 20% and `make check-full` passes |
| Depends on | `skills.1 - warden-skill-and-trial-hook` |
| Must not touch | `skills/*`, `bin/bp3`, `CONSTRAINTS.md` |

## Prose

Directly answers the blocker in `ICEBOX.md` ("False-positive budget undecided: how many junk findings per real one before the conductor stops reading? Decide with the first real report in hand."). Backtesting on 4 real quests with varying shapes (first metrics quest, followups, pi-graded quest, inline-default quest) immediately reveals whether any rule spams noise on legitimate work.
