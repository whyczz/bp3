---
date: 2026-11-23
quest: ../../QUEST.md
node: dogfood.1
status: proposed
---

# dogfood.1 - benchmark-and-sandbox-check: prove speedup, agy scrape, and wave-1 parallelism

## TL;DR

Run `bp3 q 2026-11-23-fast-agy-induct metrics scrape` and `metrics r` over this quest's own landed nodes and record the before-vs-after scorecard table in `QUEST.md` build notes, proving `agy` scrape coverage, grade wall time <= 180s median, mean cycles <= 1.5/node, and parallel wave-1 execution (`verify.1` || `agy.1` || `agy.2`).

## Acceptance gates

Observed today:

```text
$ bp3 q 2026-11-22-induct-inline-as-default-measure-author metrics r | jq -c '{grades:.rollup.grades,grade_med:.rollup.grade_wall_s.median,grade_sum:.rollup.grade_wall_s.sum}'
{"grades":16,"grade_med":377.1855,"grade_sum":6675.328}
```

Design trace:

```text
$ bp3 q 2026-11-23-fast-agy-induct metrics scrape
  - ok: true, mismatched: 0, author_bad_usage: 0
  - agy grades counted as self_checked (0 owner_graded on subagent grades)
  - agy author windows counted as authored (0 author_missing)
$ bp3 q 2026-11-23-fast-agy-induct metrics r
  - rollup.grade_wall_s.median <= 180
  - mean cycles/node <= 1.5 (or exact explanation recorded if a real bug caused extra cycles)
  - QUEST.md build notes record wave-1 ledger timestamps showing >=2 nodes overlapped in authoring
```

```yaml
objective: prove the quest hit its wall-time, cycle, agy-scrape, and parallelism targets on its own real run
prove by:
  - ./bin/bp3 q 2026-11-23-fast-agy-induct metrics scrape (output quoted verbatim in QUEST.md build notes)
  - ./bin/bp3 q 2026-11-23-fast-agy-induct metrics r (rollup quoted verbatim in QUEST.md build notes)
  - make check-full
done when: QUEST.md build notes hold the measured scorecard table comparing against 2026-11-22, agy scrape reports 0 missing/mismatched on this quest's nodes, and make check-full passes
```

## Diagram

```text
nodes verify.1..skills.1 landed on agy
   │
   ├─ bp3 q <this-quest> metrics scrape ──► verifies agy_tx on REAL transcripts
   ├─ bp3 q <this-quest> metrics r      ──► compares median grade_wall_s & cycles vs 2026-11-22
   └─ QUEST.md ## Build notes           ──► baseline vs observed table + wave-1 overlap stamps
```

## Pseudocode

```python
def benchmark_quest(q="2026-11-23-fast-agy-induct"):
    scrape = bp3_json(f"q {q} metrics scrape")
    assert scrape["ok"] is True
    readout = bp3_json(f"q {q} metrics r")
    record_scorecard_table(q, baseline_2026_11_22, readout, wave1_timestamps(q))
```

## Tables

| Field | Value |
|---|---|
| Intent | close the red-chair proof obligation with real measured numbers on `agy`, not hopes |
| Lane | micro |
| Output | `docs/quests/2026-11-23-fast-agy-induct/QUEST.md` (`## Build notes` scorecard table) |
| Acceptance | fails today (quest not yet executed on `agy`); passes when scrape + readout + build notes are recorded and verified |
| Depends on | `skills.1 - agy-induct-inline` |
| Must not touch | `src/quest/*`, `scripts/*`, `bin/bp3`, `skills/*` |

## Prose

Red-chair follow-up node (per `skills/quest/SKILL.md` step 7.5): claiming `agy` `/swarm` parallelism and `agy_tx` scraping work without measuring them on this quest's own transcripts would leave a major concern as prose. If any target (e.g. <= 180s median grade) misses on the real run, this node records the exact bottleneck honestly (never fudges numbers) so `warden-v0` has live evidence immediately.
