---
date: 2026-11-16
goal: ../GRAPH.md
exp: mig.1
status: proposed
---

# mig.1 - handoff-verbs: migrate the words first

## TL;DR

First node of the graph. The FSM verbs and state
take their settled names now — `submit -> handoff`,
`review -> grade`, `check -> verify`, state
`submitted -> handed_off` — in code, workflow
briefs, and tests. Old graph files never move and
landed ledgers are never rewritten: the fold maps
old ledger strings on read, and new ledger lines
write the new words. Every later node in this
graph is then written in the final verb vocabulary;
no double sweep, no Babel window.

## Demo (design trace)

```text
before: bp3 q old-graph u exp-x submit --commit abc -> {state: submitted}
code takes new verbs; fold gains the one compat mapping
after:  bp3 q old-graph r exp-x        -> {state: handed_off}   (files untouched)
        bp3 q old-graph u exp-x grade --verdict ship -> {state: approved}
        bp3 q old-graph u exp-x submit -> E_USAGE unknown edge (old verb gone)
this graph's own ledger: early lines say submit, later lines say
handoff — one fold reads both, by design
```

## Diagram

```text
old ledgers (frozen files) ──► fold ──compat map──► handed_off / handoff
new calls ──► handoff/grade/verify ──► ledger lines in new words only
```

## Pseudocode

```python
COMPAT = {"submit": "handoff", "review": "grade",
          "check": "verify", "submitted": "handed_off"}  # fold only, nowhere else

def fold_state(lines):
    return fold([normalize(line, COMPAT) for line in lines])
```

| Field | Value |
|---|---|
| Intent | final verb vocabulary from day one of the graph |
| Lane | high-blast-radius (touches every conducting surface) |
| Output | renamed FSM verbs/state in code + workflows + tests; one fold compat mapping; surface report |
| Depends on | none — this is the first node |

## Acceptance

| Case | Expected |
|---|---|
| old graph reads identically | an existing graph with `submit`/`submitted` ledger lines folds to `handed_off` with identical rollup before/after; no graph file modified (diff by path) |
| new verbs round-trip | fixture node: `handoff -> grade -> verify -> land` under `bp3 q … u …`; old verbs refuse as unknown edges |
| compat in one place | the old->new mapping appears only in the fold (grep shows one definition site); skills/workflows/tests contain zero old verb spellings as identifiers |
| conducting surfaces updated | `induct-exp`/`induct-grade` briefs spell `handoff`/`grade`; outcomes read `handed_off`; full `make check` green |
| this graph survives itself | this graph's own mixed-vocab ledger (early `submit`, later `handoff`) reads correctly at every step of this node |

## Acceptance test (goal block)

- **Objective:** the system speaks the new verbs
  while every old graph remains readable,
  untouched on disk.
- **Prove by:** pre/post rollup diff on a landed
  graph, fixture round-trip, grep surface report,
  `make check`.
- **Done when:** old graphs fold identically, new
  verbs conduct a fixture, files unmodified,
  observed.

## Tests

Known cases: compat fold on a frozen pre-rename
ledger fixture; unknown-edge refusal for old
verbs; mixed-vocab ledger (this graph's own shape)
folds correctly.

Property-based: for any ledger written in old
words, fold(old) == fold(migrated view) — same
state, cycle, commit on every exp.

## Context

Rename was settled last (rename.1) when the
machinery wasn't final. The verb half is final
now — settled in the names round — and it is
purely mechanical, so it goes first and every
subsequent node is authored in final words. The
noun/door/skill half (`bp3 g/n/e`, `bp3g`) still
goes last: `bp3 e` doesn't exist until mvp.2, and
the conducting skills can't rename mid-flight.
