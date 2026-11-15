---
date: 2026-11-15
quest: ../QUEST.md
exp: followup.1
status: proposed
---

# followup.1 - derivation-concurrency: parallel writers, one log

## TL;DR

Red-chair RC2: parallel Runs are the core case, but
append/rename discipline for
`run-lifecycle-derivations/` under concurrent
supervisors was never specified. Specify and prove
it: no torn rows, no lost lifecycle, no torn cache.

## Demo (design trace)

```text
supervisor A and B fold run R concurrently
  -> .jsonl rows interleave whole, sequence intact
  -> .json cache always parses (temp+rename, last writer wins whole)
```

## Diagram

```text
fold A ──┐
         ├──► <run-id>.jsonl (append-only rows)
fold B ──┘         └─► <run-id>.json (atomic rename cache)
```

## Pseudocode

```python
append_row(path, row)     # single write() per row, O_APPEND
write_cache(path, snap)   # temp file in same dir + rename
```

| Field | Value |
|---|---|
| Intent | make the derived store safe under the parallelism it exists for |
| Lane | standard |
| Output | writer discipline in mvp.1/mvp.4 code path + concurrency fixtures |
| Depends on | mvp.1 |

## Acceptance (fails today: discipline unspecified)

| Case | Expected |
|---|---|
| 2 supervisors, same run, 100 ticks | every `.jsonl` line parses; no row lost or torn |
| cache write race | `.json` always valid JSON; fingerprint check catches staleness |
| reader during append | reader sees whole rows only; torn tail ignored and reported |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the proof store survives its own parallelism.
- **Prove by:** concurrent-fold fixture with forced interleavings.
- **Done when:** parse-all-lines and cache-validity checks pass under race fixtures.

## Context

From the post-adoption red-chair (RC2). Local,
single-machine scope: filesystem append/rename
semantics only, no locks service, no daemon.

## Tests

Known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). Property-based: for
any interleaving of N writers x M rows, the log is
a merge of whole rows and fold result equals the
sequential fold of the same rows.
