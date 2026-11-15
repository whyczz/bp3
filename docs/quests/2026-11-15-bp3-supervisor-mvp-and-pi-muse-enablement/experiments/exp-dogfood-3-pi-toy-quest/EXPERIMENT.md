---
date: 2026-11-15
quest: ../QUEST.md
exp: dogfood.3
status: proposed
---

# dogfood.3 - pi-toy-quest: flappy bird on pi, supervised

## TL;DR

dogfood.1's toy quest, driven on pi under the
supervisor per dogfood.2's design: pi children spawn,
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
drive(toy_quest, engine="pi")   # dogfood.2 design
assert landed and lifecycles_derived()
```

| Field | Value |
|---|---|
| Intent | pi engine MVP proven live under supervision |
| Lane | standard |
| Output | toy quest landed on pi; demo artifact; traces |
| Depends on | dogfood.2 |

## Acceptance (fails today: pi engine canceled)

| Case | Expected |
|---|---|
| full drive on pi | toy exp `exp_fin`; Runs derived from pi WAL |
| hung pi child (seeded) | watchdog kills; orphaned, never settled |
| model cast | roles run their configured models (dogfood.2 decides cast) |

## Acceptance test (goal block)

- **Objective:** pi drives real work under the
  supervisor.
- **Prove by:** the drive + artifact + traces.
- **Done when:** toy landed on pi, observed.

## Tests

quest-level functional drive. Known cases: clean
drive; seeded hung pi child is TERM/KILLed by
watch inside budget and lands `orphaned`, never
`finished`; seeded silent child past
--silence-seconds. Property-based: supervisor is
sole killer — no other component signals a pid in
any drive trace. Demos: drive + flappy page smoke,
observed.

## Context

Same toy as dogfood.1 on purpose: one variable changes
(the engine), so the comparison means something.

## Auto-red-ink addendum

This exp currently assumes an engine dogfood.2 only
designs. Add substep 10.1: port/re-verify the
dispatcher + pi lookup/watch against the new
verdict shapes with the fake-pi suite
(clean/hung/drip/closed-not-exited/crash/malformed/
self-settling child). The toy drive is 10.2 and may
not be used as the first proof of the binding.
Hardening tests:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Pi implementation + cross-engine contract table).
