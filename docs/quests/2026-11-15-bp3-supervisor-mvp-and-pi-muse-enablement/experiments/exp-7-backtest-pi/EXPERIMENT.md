---
date: 2026-11-15
quest: ../QUEST.md
exp: 7
status: proposed
---

# Exp 7 — backtest-pi: the pi corpus, five known incidents

## TL;DR

Same replay over pi session files (live spawns from
the canceled quest): the fold faces its exam
corpus — five incidents with ledger truth — plus
whatever the pi WAL shape teaches the adapters.

## Demo (design trace)

```text
incidents: c1 unwitnessed / c2 fossil / c3 settled /
           2b refusals x2 / 2a unsettleable
replay -> derived vs truth, diffs -> findings
```

## Diagram

```text
pi session files (.bp3-pi/sessions, run desks)
  ─► adapter fold ─► traces ─► vs ledger ─► findings.md
```

## Pseudocode

```python
for s in corpus("pi"):
    findings += diff(derive(fold(parse(s))), ledger_truth(s))
```

| Field | Value |
|---|---|
| Intent | measure the pi fold; harvest adapter/dispatcher fix candidates |
| Lane | standard |
| Output | replay report + findings list |
| Depends on | Exp 2 (pi lookup), Exp 6 (harness shared) |

## Acceptance (fails today: no replay exists)

| Case | Expected |
|---|---|
| five incidents replayed | each derived or explained as a finding |
| pi WAL quirks | adapter gaps listed with file/line evidence |
| findings | proposed fix targets named (dispatcher, adapter, contract) |

## Acceptance test (goal block)

- **Objective:** pi fold measured against the
  hardest corpus we own.
- **Prove by:** replay over canceled-quest pi runs.
- **Done when:** report + findings exist for owner
  disposition.

## Tests

findings-machine (as Exp 6). Sanity: fold totals
(usage) match session-file sums on sampled runs.
Demos: incident replays observed.

## Context

The five incidents (exp-2 c1-c3, exp-2b refusals,
exp-2a unsettleable) were blocks when live; as a
corpus they are the cheapest supervision exam in
the repo.
