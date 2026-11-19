---
date: 2026-11-15
goal: ../QUEST.md
exp: followup.2
status: proposed
---

# followup.2 - finish-evidence: what closes a tape?

## TL;DR

Red-chair RC3: `finished` requires tape closed, but
muse tapes may have no close marker. Define, per
adapter, what finish evidence is (close marker,
exit entry, pid dead + final-entry shape) — proved
against real corpora, not assumed.

## Demo (design trace)

```text
muse child exits; tape has no close marker
  -> adapter rule: exit entry + pid dead + no growth
     for grace budget => finished
```

## Diagram

```text
tape end shape + pid + grace ──► finished?
per-adapter evidence table, corpus-proved
```

## Pseudocode

```python
def finished(adapter, run):
    return adapter.finish_evidence(run.tape_tail,
           run.pid, run.grace_expired)
```

| Field | Value |
|---|---|
| Intent | make `finished` reachable on real tapes for both engines |
| Lane | standard |
| Output | per-adapter finish-evidence table + corpus fixtures |
| Depends on | mvp.2; feeds backtest.1/backtest.2 |

## Acceptance (fails today: close marker assumed)

| Case | Expected |
|---|---|
| muse run, exit entry, no close marker | derives `finished` inside grace budget |
| live long-quiet muse run | never `finished` early (pid alive wins) |
| pi run, process exit | derives `finished` |
| tape truncated mid-entry | not `finished`; blind/torn handling fires |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Finish evidence (proved on the real corpora)

Only the last whole tape entry can carry finish
evidence; a marker named mid-tape is content.

| Harness | Finish evidence (last whole entry) | Exit entry |
|---|---|---|
| `muse-code` | `session.end` entry (close marker) | runtime `terminal` entry — a child tape ends here, with no close marker |
| `pi` | `session_closed` entry, or a final assistant entry with stopReason `stop` | process exit (pid dead); pi tapes never close |

A torn final entry finishes nothing and warns
`W_TORN_TAIL`. A live pid is never `finished`.

## Acceptance test (goal block)

- **Objective:** `finished` is derivable on every real tape shape we own.
- **Prove by:** corpus fixtures from backtest tapes, incl. no-close-marker runs.
- **Done when:** all Acceptance cases derive the named lifecycle.

## Context

From the post-adoption red-chair (RC3). If a corpus
shows an engine whose finish is underivable, that
is a finding for dogfood.2, not a silent rule bend.

## Tests

Known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). Property-based: for
any tape whose pid is alive, lifecycle is never
`finished` regardless of tail shape.
