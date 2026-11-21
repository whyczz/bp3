---
date: 2026-11-21
quest: ../../QUEST.md
node: sink.1
status: proposed
---

# sink.1 - sample-sink: one sample shape, one owner per metric, one file per node

## TL;DR

`src/quest/metrics.ml` defines the sample type and the registry.
Appends go to `metrics.jsonl` on the node's state branch through
`Gitx.commit_files`: one commit per node per batch, and a sample
already there is skipped. `bp3 q <quest> metrics r` reads them back
as JSON. There are no collectors yet; this node is the floor the
scrapers stand on.

## Acceptance gates

Observed today:

```text
$ bp3 q 2026-11-19-constraints-context metrics r
{"ok":false,"error":{"code":"E_USAGE",...}}        # rc=2, 2026-11-21
```

Design trace:

```text
$ dune test                       # metrics unit rows
registry: 0 duplicate names, every metric has one owner
append [s1; s2; s1] -> written 2, skipped 1 (key: metric, node, cycle, run)
append {metric="grade.nope"} -> E_METRIC_UNKNOWN
append {metric="grade.wall_s", source="author-window"} -> E_METRIC_OWNER
append {model="claude opus; rm"} -> E_METRIC_VALUE (ids only)
$ bp3 q <quest> metrics r         # empty sink
{"ok":true,"quest":"<quest>","nodes":{"node-a":{"cycles":{}}}}
$ bp3 q r <quest> > a; <append a batch>; bp3 q r <quest> > b; diff a b   # empty: rollup untouched
```

```yaml
objective: samples can be written once, read back, and never carry text or a second owner
prove by:
  - dune test (new metrics unit rows, with a QCheck law that appending any batch twice writes it once)
  - a fixture in test/ that appends through the OCaml path in a planted repo and reads with metrics r
  - make check-full
done when:
  - every design-trace line above holds
  - one batch of 30 samples on one node is exactly one new commit on refs/heads/bp3/node/<quest>/<node>
  - bp3 q r output is byte-identical before and after an append
```

## Diagram

```text
collector ── [sample] ──> validate ──> dedupe vs metrics.jsonl ──> Gitx.commit_files (CAS)
                            |  E_METRIC_UNKNOWN | E_METRIC_OWNER | E_METRIC_VALUE
bp3 q <quest> metrics r ──> read metrics.jsonl per node ──> group by cycle, kind ──> JSON
```

## Pseudocode

```python
@dataclass(frozen=True)
class Sample:
    metric: str; quest: str; node: str; cycle: int
    run: str          # "claude:<sessionId>/<agentId>" | "claude:<sessionId>"
    model: str        # id: [a-z0-9.-]+
    value: float      # finite
    at: str           # ISO 8601, end of the measured thing
    source: str       # collector name, a registry owner

REGISTRY = {  # metric: (unit, agg, owner)
    "grade.wall_s": ("s", "sum", "grade-transcripts"),
    "grade.tool_calls": ("count", "sum", "grade-transcripts"),
    "grade.context_end": ("tokens", "max", "grade-transcripts"),
    "grade.tokens_in" ... "grade.tokens_cache_write": ("tokens", "sum", "grade-transcripts"),
    "author.tool_calls", "author.tokens_*": (..., "author-window"),
    "timing.*": (..., "timing"),   # existing render.ml deriver, listed so one owner is visible
}

def append(quest, node, batch):
    for s in batch: validate(s)                     # refuse the whole batch on one bad sample
    have = {key(s) for s in read(quest, node)}
    new = [s for s in batch if key(s) not in have]
    if new: commit_files(node_branch, [(path, old_text + lines(new))])  # one commit
    return {"written": len(new), "skipped": len(batch) - len(new)}
```

## Tables

| Field | Value |
|---|---|
| Intent | a sink and a registry the scrapers write through, nothing else |
| Lane | standard (a new GENERATED file on state branches) |
| Output | `src/quest/metrics.ml`, the `metrics r` door in `src/quest/main.ml`/`cli.ml`, unit rows, one fixture, a `test/suites.tsv` row |
| Acceptance | the design trace above; `metrics r` is `E_USAGE` today |
| Depends on | none |

| Case | Result |
|---|---|
| metric not in the registry | `E_METRIC_UNKNOWN`, nothing written |
| `source` is not the metric's owner | `E_METRIC_OWNER`, nothing written |
| non-finite value, bad `model` or `run` id | `E_METRIC_VALUE`, nothing written |
| same key appended again | skipped, counted |
| branch tip moved mid-append | `E_STALE_WORLD` from `Gitx.commit_files`; caller re-reads |
| node with no `metrics.jsonl` | `metrics r` shows `{"cycles":{}}` |

## Prose

Why the sink comes first and stays this small: three collectors
writing their own files is the "two frameworks" risk the icebox
entry names. Every number goes through one door, so the
one-owner rule is enforced in code, not by convention.

Why no free text: transcripts hold prompts and may hold secrets,
and node state branches get pushed with the repo. A sample holds
numbers and ids only, so a scraper bug cannot leak a prompt into
git (QUEST.md, R4).

Why one commit per batch: git as a database is already bp3's
slowest path (`docs/icebox/2026-11-18-sqlite-store.md`: 185 git
spawns for one rollup). One commit per sample would add hundreds
(R5).

Derived numbers are not stored. derive.1 computes them when
`metrics r` runs, so they can't go stale.
