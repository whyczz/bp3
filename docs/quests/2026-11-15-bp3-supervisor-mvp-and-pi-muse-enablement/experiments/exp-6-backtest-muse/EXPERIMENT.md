---
date: 2026-11-15
quest: ../QUEST.md
exp: 6
status: proposed
---

# Exp 6 — backtest-muse: findings, not a gate

## TL;DR

Replay the fold over the stored muse session corpus
(this session's quest children included): extract
bp3 invocations, `E_*` refusals, git commits, and
exits per Run; compare with ledger truth; emit a
findings list — candidate fixes for `bp3 q u`,
hooks, and the adapters. It need not pass. It must
be legible.

## Demo (design trace)

```text
replay(01a1de19-...) -> submit 88c4b6f matches ledger;
  no settle marker -> derived orphaned. truth: fossil. FINDING: none (fold right)
replay(2b-refusal)   -> E_BINDING_REFUSED found; no submit. truth: honest stop. MATCH
```

## Diagram

```text
muse WAL corpus ─► adapter fold ─► traces ─► vs ledger ─► findings.md
                                                       (fixes: q u / hooks / adapter)
```

## Pseudocode

```python
for s in corpus("muse"):
    tr = fold(parse(s))
    d = diff(derive(tr), ledger_truth(tr))
    if d: findings.add(tr.run_id, d)
```

| Field | Value |
|---|---|
| Intent | validate + improve the fold on real muse logs; harvest CLI fix candidates |
| Lane | standard |
| Output | replay report + findings list in this exp's runs |
| Depends on | Exp 2, Exp 4 |

## Acceptance (fails today: no replay exists)

| Case | Expected |
|---|---|
| corpus replay completes | trace per identifiable Run |
| known incidents in corpus | derived == truth, or finding explains the gap |
| findings list | each finding: run-id, evidence lines, proposed fix target |

## Acceptance test (goal block)

- **Objective:** the muse fold is measured, and
  its failures are a fix list, not a surprise.
- **Prove by:** replay over the pi-quest day's
  sessions.
- **Done when:** report exists; owner can pick
  findings to promote.

## Tests

findings-machine: no pass/fail acceptance by
design (owner rule). Sanity checks: parser never
crashes on truncated/foreign files. Demos: replay
excerpt observed.

## Context

Owner ruling at framing: backtests determine fixes
(e.g. to `bp3 q u`), they don't gate. Ground truth
is ledger + grade matrices, read after deriving.
