---
date: 2026-11-15
quest: ../QUEST.md
exp: 8
status: proposed
---

# Exp 8 — muse-toy-quest: flappy bird under supervision

## TL;DR

Live proof on muse: a toy quest — build a flappy
bird demo in three.js — driven by subagents while
`bp3 harness supervisor` watches. The toy exp
travels todo -> landed with derived lifecycle, no
LLM polling, no witness rituals in child briefs.

## Demo (design trace)

```text
supervisor --quest toy-flappy
  author run: WAL grows, commits, submit -> settled
  grade runs: parallel, watched -> landed
scorecard: warnings only if a Run misbehaves
```

## Diagram

```text
toy quest ─► supervisor loop ─► subagents (author/grade/land)
                  │ watch/fold        └─► three.js flappy demo
                  ▼
             exp_fin, traces recorded
```

## Pseudocode

```python
drive(toy_quest)            # induct, supervisor as mechanism (Exp 4)
assert exp.state == landed and all_runs_derived()
```

| Field | Value |
|---|---|
| Intent | Phase C live demo: supervisor + muse + real subagent work |
| Lane | standard |
| Output | toy quest landed; flappy demo artifact; drive traces |
| Depends on | Exp 1-5; findings disposition from Exp 6 |

## Acceptance (fails today: supervisor not the mechanism)

| Case | Expected |
|---|---|
| full drive | toy exp `exp_fin`; every Run lifecycle derived |
| child briefs | zero prefix/witness instructions needed |
| demo artifact | flappy bird page exists and opens |

## Acceptance test (goal block)

- **Objective:** the supervisor supervises real
  work, not fixtures.
- **Prove by:** the drive itself + artifact.
- **Done when:** toy landed; traces + artifact in
  this exp's runs.

## Tests

quest-level functional drive (this exp is the
test). Demos: drive observed; flappy page smoke.

## Context

First live gate for the whole design. Findings
from Exp 6 land first if they touch the drive path.
