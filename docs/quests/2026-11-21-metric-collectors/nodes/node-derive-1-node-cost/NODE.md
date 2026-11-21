---
date: 2026-11-21
quest: ../../QUEST.md
node: derive.1
status: proposed
---

# derive.1 - node-cost: roll-ups computed on read, from samples and the ledger

## TL;DR

A pure deriver turns samples and ledger edges into per-cycle
timing (`cycle.todo_s`, `cycle.handed_off_s`) and per-node and
per-quest roll-ups (grades, spend by token field, median grade
wall). `metrics r` prints them. Nothing derived is stored.

## Acceptance gates

Observed today: `bp3 q r` gives per-node `timing.dwell_s`, summed
over cycles. The fast-grader table ("median about 11 min (4-37)")
was computed by hand.

Design trace:

```text
$ bp3 q 2026-11-18-test-pyramid metrics r | jq '.quest'
{"nodes":11,"grades":<n>,"grade_wall_s":{"median":<n>,"min":<n>,"max":<n>},
 "spend":{"tokens_in":<n>,"tokens_out":<n>,"tokens_cache_read":<n>,"tokens_cache_write":<n>},
 "unmatched":{"owner":<n>,"ambiguous":<n>,"mismatched":<n>}}
$ bp3 q 2026-11-19-constraints-context metrics r | jq '.nodes["node-rules-4-lint-hardening"].cycles["4"].timing'
{"todo_s":8,"handed_off_s":1370}      # 20:52:01 resume -> 20:52:09 handoff -> 21:14:59 grade
```

```yaml
objective: every roll-up in metrics r is a pure function of samples plus ledger, and agrees with the hand numbers it replaces
prove by:
  - dune test: known cases (the rules.4 cycle 4 timing above; a quest with an owner-graded cycle) and QCheck laws:
    derive(xs) == derive(shuffle(xs)); sum over nodes == quest total; derive is unchanged by an empty append
  - metrics r on test-pyramid, compared with fast-grader's hand table (grade wall median about 11 min, range 4-37)
  - make check-full
done when:
  - the laws hold, and cycle 4 timing reads todo_s 8, handed_off_s 1370
  - the test-pyramid median grade wall is within a minute of fast-grader's hand number, and any difference is explained in the handoff reason
  - per-cycle todo_s summed over cycles equals bp3 q r's timing.dwell_s.todo for every node
```

## Diagram

```text
ledger edges ─┐
              ├─> derive (pure) ─> cycle timing, node roll-up, quest roll-up ─> metrics r JSON
samples ──────┘                     (never written back)
```

## Pseudocode

```python
def derive(edges, samples):
    cycles = {}
    for node, cyc, t_todo, t_hand, t_grade in cycle_spans(edges):
        cycles[node, cyc] = {"timing": {"todo_s": t_hand - t_todo, "handed_off_s": t_grade - t_hand},
                             "grade": fold(samples, node, cyc, "grade."),     # registry agg per metric
                             "author": fold(samples, node, cyc, "author.")}
    nodes = {n: rollup(c for (m, _), c in cycles.items() if m == n) for n in node_ids(edges)}
    quest = rollup(nodes.values()) | {"grade_wall_s": stats(s.value for s in samples if s.metric == "grade.wall_s")}
    return cycles, nodes, quest
```

## Tables

| Field | Value |
|---|---|
| Intent | the numbers people ask about, computed one way |
| Lane | standard |
| Output | the deriver in `src/quest/metrics.ml`, `metrics r` roll-ups, unit rows |
| Acceptance | the laws and the timing row above; the per-cycle split does not exist today |
| Depends on | scrape.1 - grade-transcripts, scrape.2 - author-window |

| Number | Owner |
|---|---|
| `cycle.todo_s`, `cycle.handed_off_s` | this deriver, from the ledger |
| `timing.*` in `bp3 q r` | the existing render.ml deriver; unchanged, and the sum law ties the two together |
| grade and author fields | the scrapers; this node only folds them |

## Prose

Computed on read, because a stored roll-up goes stale the moment a
late scrape lands. The input is small (one quest's samples), so
recomputing every time costs nothing next to the git reads.

The sum law, per-cycle todo summed against `bp3 q r`'s
`dwell_s.todo`, is the guard against having two derivers that
disagree. The old number stays where it is, and the new split has
to add up to it.
