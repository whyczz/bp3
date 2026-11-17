---
date: 2026-11-15
goal: ../GRAPH.md
exp: mvp.6
status: proposed
---

# mvp.6 - harness-desk-api: one namespace for the machinery

## TL;DR

API alignment: `bp3 worktree` folds into
`bp3 harness desk` (prepare/list/release), so every
harness-facing verb lives under one door. Callers,
skills, and tests migrate; old door's fate
(alias vs hard cut) settled here with evidence.

## Demo (design trace)

```text
bp3 harness desk prepare --quest Q -> {path}
bp3 harness desk list              -> desks + quests
bp3 harness desk release --quest Q -> released | refused (dirty)
```

## Diagram

```text
bp3 worktree * ──► bp3 harness desk *   (same store module: desk.ml)
skills/tests callers ──► updated spellings
```

## Pseudocode

```python
door("harness", ["desk", verb]) == door("worktree", verb)  # during migration
```

| Field | Value |
|---|---|
| Intent | namespace consolidation; no behavior change beyond spelling |
| Lane | standard |
| Output | `bp3 harness desk` + migrated callers/skills/tests |
| Depends on | mvp.1 |

## Acceptance (fails today: two namespaces)

| Case | Expected |
|---|---|
| desk prepare/list/release via harness door | identical verdicts to old door |
| repo-wide caller sweep | no live caller on retired spelling (or alias documented) |
| `make check` | green |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** one door for harness machinery.
- **Prove by:** verb-parity fixture + grep sweep.
- **Done when:** parity green; sweep clean.

## Tests

known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). property-based:
none. Demos: parity fixture observed.

## Context

The worktree->desk rename already happened in code
(`desk.ml`, Exp 1 of the canceled pi quest); this
finishes it at the CLI surface where users live.

## Auto-red-ink addendum

Correction: on the main tree the module is still
`worktree.ml`, records live under `.bp3/desks/`,
paths under `.bp3/worktrees/`; a third spelling
`bp3 desk` exists in the canceled worktree. This exp
must map all nine verbs, capture golden verdict
fixtures before migration (including dirty refusal),
and sweep help, completions, skills, and tests.
Creation must refuse reserved door/verb slugs.
Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(golden parity fixtures; reserved-name refusals).
