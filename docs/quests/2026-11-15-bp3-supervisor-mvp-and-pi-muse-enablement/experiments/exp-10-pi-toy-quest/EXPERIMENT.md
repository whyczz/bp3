---
date: 2026-11-15
quest: ../QUEST.md
exp: 10
status: proposed
---

# Exp 10 — pi-toy-quest: flappy bird on pi, supervised

## TL;DR

Exp 8's toy quest, driven on pi under the
supervisor per Exp 9's design: pi children spawn,
WALs fold, watch supervises, exp lands.

## Demo (design trace)

```text
supervisor --engine pi --quest toy-flappy-pi
  author (sol) -> settled; grade (astra/terra) -> landed
```

## Diagram

```text
toy quest ─► supervisor ─► pi children (dispatcher)
                  │ fold pi WAL     └─► flappy demo
                  ▼
             exp_fin, traces recorded
```

## Pseudocode

```python
drive(toy_quest, engine="pi")   # Exp 9 design
assert landed and lifecycles_derived()
```

| Field | Value |
|---|---|
| Intent | pi engine MVP proven live under supervision |
| Lane | standard |
| Output | toy quest landed on pi; demo artifact; traces |
| Depends on | Exp 9 |

## Acceptance (fails today: pi engine canceled)

| Case | Expected |
|---|---|
| full drive on pi | toy exp `exp_fin`; Runs derived from pi WAL |
| hung pi child (seeded) | watchdog kills; orphaned, never settled |
| model cast | roles run their configured models (Exp 9 decides cast) |

## Acceptance test (goal block)

- **Objective:** pi drives real work under the
  supervisor.
- **Prove by:** the drive + artifact + traces.
- **Done when:** toy landed on pi, observed.

## Tests

quest-level functional drive. Demos: drive +
flappy page smoke, observed.

## Context

Same toy as Exp 8 on purpose: one variable changes
(the engine), so the comparison means something.
