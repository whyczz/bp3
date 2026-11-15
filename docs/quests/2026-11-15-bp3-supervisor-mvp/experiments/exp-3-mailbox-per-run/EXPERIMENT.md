---
date: 2026-11-15
quest: ../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — mailbox-per-run: one writer per Run

## TL;DR

The muse writer still appends to one shared mutable
session dict — the file that raced and fossilized.
Migrate to per-Run `.git/bp3-run-events/<run_id>.jsonl`
(the pi side's Exp 2 shape from the canceled quest);
readers fold; the legacy dict is read-only, named
legacy, with a stated sunset.

## Demo (design trace)

```text
.git/bp3-run-events/
  20261115T...-submit-...-c1.jsonl   {run_started} {heartbeat} {run_settled}
  20261115T...-review-...-c1.jsonl   {run_started} {usage_recorded} ...
list_runs -> fold of the above; legacy file untouched
```

## Diagram

```text
emitters ──append──► per-Run .jsonl (single writer each)
readers  ──fold────► lifecycle views (derived, disposable)
legacy bp3-run-events.json ──read-only──► named legacy, sunset stated
```

## Pseudocode

```python
def emit(run_id, row): append(f".git/bp3-run-events/{run_id}.jsonl", row)
def fold_all(): return [fold_file(f) for f in glob("*.jsonl")] + legacy_view()
```

| Field | Value |
|---|---|
| Intent | mailbox storage shape: append-only, single-writer, per Run |
| Lane | standard |
| Output | hooks writer migration + fold readers + legacy sunset note |
| Depends on | Exp 2 |

## Acceptance (fails today: muse writes the shared dict)

| Case | Expected |
|---|---|
| two parallel Runs emit | two files, zero interleaved/torn rows |
| reader with legacy file present | folds both, labels legacy rows legacy |
| writer crash mid-append | at most one torn last line; fold skips it |

## Acceptance test (goal block)

- **Objective:** no shared mutable witness file
  remains on the muse write path.
- **Prove by:** parallel-emit fixture + fold diff
  against pre-migration behavior.
- **Done when:** fixture green; legacy file mtime
  unchanged during new writes.

## Tests

known cases: Acceptance table. property-based:
concurrent appends from N emitters lose zero rows.
Demos: parallel fixture output, observed.

## Context

Carried over verbatim in intent from the canceled
pi quest's Exp 8: the desks fix (one file per Run
ID) already proved this shape in this codebase.
