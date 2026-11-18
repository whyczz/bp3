---
date: 2026-11-15
goal: ../GRAPH.md
exp: 8
status: proposed
---

# Exp 8 — muse-event-log-per-run: the muse writer moves to per-Run files

## TL;DR

Round 3 settled event log storage for every harness:
`.git/bp3-run-events/<run_id>.jsonl`, one file per Run,
folded on read. Pi writes that way from birth (Exp 4);
the muse hooks/workflows still write the single legacy
`.git/bp3-run-registry.json` (Exp 1 renames the word;
this exp migrates the storage and the keying — files
and folds key on run-id, session_id becomes a field).
This exp migrates the muse writer and every reader,
so the convention describes one storage shape, not two.

## Diagram

```text
before: hooks -> .git/bp3-run-registry.json (one session-keyed dict, raced before)
after:  hooks -> .git/bp3-run-events/<run_id>.jsonl  (append own Run only, keyed by run-id)
readers: fold directory (+ legacy file read-only,
         named legacy in output, until a stated sunset)
```

## Pseudocode

```python
def emit(run_id, row):
    append(f".git/bp3-run-events/{run_id}.jsonl", json(row))

def fold(run_id=None):
    rows = read_all(".git/bp3-run-events/*.jsonl")
    return rows  # legacy file NOT merged silently
```

| Field | Value |
|---|---|
| Intent | one event log convention, both engines, no silent dual-read |
| Lane | standard (hooks + readers in `src/`, workflow scripts, tests) |
| Output | per-Run writer in the hooks path, re-keyed: files and folds key on run_id (the primary key), session_id demoted to a witnessed field; fold reader; legacy file read-only with a named sunset condition |
| Depends on | Exp 2.1 (convention defined + fold specified) |

## Acceptance (fails today: muse writes one shared JSON file)

| Case | Expected |
|---|---|
| per-Run write | one muse workflow Run leaves `.git/bp3-registry/<run_id>.jsonl` with its started/usage/settled rows; the legacy file's mtime unchanged |
| parallel safety | two simultaneous Runs produce two files, zero lost rows (the historical race, regression-tested) |
| reader fold | grade adherence queries read per-Run files and quote the same rows the old reader quoted for a legacy Run |
| no silent merge | a read that touches the legacy file says so (`legacy: true` in output facts); sunset removes the legacy path when no live quest cites it |

## Acceptance test (goal block)

- **Objective:** muse event evidence lives in
  per-Run files; readers fold; nothing silently merges.
- **Prove by:** one live muse step Run + the parallel
  regression test in `make check`.
- **Done when:** new file present, legacy untouched,
  race test green.

## Tests

known cases: Acceptance table · property-based: fold of
N per-Run files equals the row multiset written ·
fixtures: hooks tests, simulated parallel emitters ·
demos: the live Run's event log file, observed.

## Context

Appended at red-ink (owner, round 3 follow-up) so the
shared convention never describes two storage shapes.
The desks fix (one file per Run ID) already proved this
shape in this codebase; this exp applies the same
lesson to the event log instead of re-learning it.
