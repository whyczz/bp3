---
date: 2026-11-15
goal: ../GRAPH.md
exp: backtest.1
status: proposed
---

# backtest.1 - muse: findings, not a gate

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
| Depends on | mvp.2, mvp.4 |

## Acceptance (fails today: no replay exists)

| Case | Expected |
|---|---|
| corpus replay completes | trace per identifiable Run |
| known incidents in corpus | derived == truth, or finding explains the gap |
| findings list | each finding: run-id, evidence lines, proposed fix target |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the muse fold is measured, and
  its failures are a fix list, not a surprise.
- **Prove by:** replay over the pi-quest day's
  sessions.
- **Done when:** report exists; owner can pick
  findings to promote.

## Tests

findings-machine: no pass/fail acceptance by
design (owner rule); env-set run-id is stamped by
bp3 into the submit verdict and ledger line (the
mvp.1 mechanism). Known cases: truncated tape,
foreign (non-bp3) tape, torn final line — parser
never crashes, reports shape. Property-based: for
any tape prefix, replay yields a prefix-consistent
trace (facts never appear before their entry).
Hardening: [TEST-HARDENING.md](../../TEST-HARDENING.md)
(Muse implementation rows). Demos: replay excerpt
observed.

## Context

Owner ruling at framing: backtests determine fixes
(e.g. to `bp3 q u`), they don't gate. Ground truth
is ledger + grade matrices, read after deriving.

## Auto-red-ink addendum

Dependency drops to mvp.2 + fold definition; replay
is offline and may precede mvp.4. Report the corpus
denominator (runs replayed / identifiable), incident
match counts, and mark lifecycle claims without an
independent InitRecord `ungradeable`, not findings.
A parser crash fails this exp even though findings
do not gate. Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(backtest reporting; Muse adapter drift cases).
