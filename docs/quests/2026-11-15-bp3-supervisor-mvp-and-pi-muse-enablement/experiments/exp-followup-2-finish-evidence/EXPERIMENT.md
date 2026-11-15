---
date: 2026-11-15
quest: ../QUEST.md
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

## Acceptance test (goal block)

- **Objective:** `finished` is derivable on every real tape shape we own.
- **Prove by:** corpus fixtures from backtest tapes, incl. no-close-marker runs.
- **Done when:** all Acceptance cases derive the named lifecycle.

## Context

From the post-adoption red-chair (RC3). If a corpus
shows an engine whose finish is underivable, that
is a finding for dogfood.2, not a silent rule bend.

## Tests

Known cases: Acceptance table. Property-based: for
any tape whose pid is alive, lifecycle is never
`finished` regardless of tail shape.
