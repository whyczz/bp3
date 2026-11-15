---
date: 2026-11-15
quest: ../QUEST.md
exp: 1
status: proposed
---

# Exp 1 — wal-backtest: prove the fold on yesterday's corpses

## TL;DR

Before any live supervision: parse the harness WALs
we already have (muse session store, pi session
files from the canceled pi quest) into a normalized
event stream, fold each Run's trace, and check the
derived lifecycle against ledger ground truth. The
exam is five known incidents; a fold that cannot
reproduce history earns nothing live.

## Demo (design trace)

```text
replay(session 01a1de19-..., exp-2 c2 author)
  -> bp3 calls: [submit --commit 88c4b6f...]  refusals: []
  -> events: run_started only; WAL silent 07:53 -> end
  -> derived: orphaned        ledger truth: fossil (blocked c2)  MATCH
```

## Diagram

```text
~/.local/share/muse/sessions/**.jsonl ─┐
pi session files (.bp3-pi/sessions) ───┤ adapters
                                       ▼
                          normalized events (jsonl)
                          {run?, session, ts, kind, facts}
                                       │ fold
                                       ▼
              trace per Run -> derived lifecycle
                                       │ compare
                                       ▼
              ledger.jsonl ground truth -> exam verdict
```

## Pseudocode

```python
for session in corpus:
    ev = adapter.parse(session)               # mechanical facts only
    tr = fold(ev)                             # bp3 q calls, git commits,
                                              # E_* refusals, usage, close
    got = lifecycle(tr)
    want = ledger_truth(tr.run_id)            # read AFTER deriving
    exam.record(tr.run_id, got == want, diff(got, want))
```

| Field | Value |
|---|---|
| Intent | adapters + replay harness + the five-incident exam |
| Lane | standard |
| Output | `tools/wal/` (adapters, fold, replay CLI) + exam report in this exp's runs |
| Depends on | none |

## Acceptance (fails today: no adapters, no fold, no replay)

| Case | Fold must derive (from WAL alone) |
|---|---|
| exp-2 c1 author | submitted, unwitnessed (no bind evidence) |
| exp-2 c2 author | `run_started`, never settled -> fossil/orphaned |
| exp-2 c3 author | full lifecycle -> settled |
| exp-2b c2 authors (x2) | `E_BINDING_REFUSED`, honest stop, no submit |
| exp-2a c1 author | bound, agent linkage empty -> unsettleable |

## Acceptance test (goal block)

- **Objective:** replay reproduces all five
  incidents from raw WAL, zero ledger peeking.
- **Prove by:** `wal replay --corpus <pi-quest sessions>`
  exam report comparing derived vs ledger truth.
- **Done when:** 5/5 match, each with the diff shown
  for any near-miss.

## Tests

known cases: the five incidents (exam corpus, frozen
inputs). property-based: shuffled/interleaved
session files fold to identical traces; truncated
last lines never crash the fold. Demos: replay of
one incident, observed, in this exp's notes.

## Context

This is the session-log-mining icebox
(`docs/icebox/2026-11-13-session-log-mining.md`)
promoted sideways: same scraper, pointed at
supervision. Mining said never write state from
scrapes; the backtest honors it by deriving only,
against ledger truth it reads last.
