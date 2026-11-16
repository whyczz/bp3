---
date: 2026-11-15
quest: ../QUEST.md
exp: dogfood.1
status: proposed
---

# dogfood.1 - muse-toy-quest: flappy bird under supervision

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
drive(toy_quest)            # induct, supervisor as mechanism (mvp.4)
assert exp.state == landed and all_runs_derived()
```

| Field | Value |
|---|---|
| Intent | Phase C live demo: supervisor + muse + real subagent work |
| Lane | standard |
| Output | flappy demo artifact from the exp Run; supervisor derivation traces for that Run |
| Depends on | mvp.1-mvp.6, mvp.8 (InitRecord writer); findings disposition from backtest.1 |

## Acceptance (fails today: supervisor not the mechanism)

| Case | Expected |
|---|---|
| demo run (owner edit: demo as an experiment, not a full induct) | the exp's own submit Run produces the flappy demo artifact; the supervisor derives that Run's lifecycle from its tape (`init`/`active`/`finished`) with derivation pointers. No toy quest, no nested induct — nested quests/inducts are out of scope for this quest (owner ruling) |
| child briefs | zero prefix/witness instructions needed |
| demo artifact | flappy bird page exists and opens |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the supervisor supervises real
  work, not fixtures.
- **Prove by:** the exp Run itself + artifact.
- **Done when:** the submit Run's lifecycle is
  derived by the supervisor; artifact in this
  exp's runs.

## Tests

quest-level functional drive (this exp is the
test); env-set run-id is stamped by bp3 into the
submit verdict and ledger line (the mvp.1
mechanism). Known cases: clean drive to `finished`;
seeded blind Run (W_SUPERVISOR_BLIND logged, empty
data, drive proceeds — feeds the U8 veto call);
seeded hung child in passive mode is reported,
never killed by bp3. Property-based: no drive step
requires an LLM poll — tick count is wall-clock
bounded. Demos: drive observed; flappy page smoke.

## Context

First live gate for the whole design. Findings
from backtest.1 land first if they touch the drive path.

## Auto-red-ink addendum

Muse's runtime drives; the supervisor only derives.
Add the owner decision row: seed a blind-log Run,
then record `veto | warn-only` for supervisor
warnings at landing. If any backtest.1 finding is marked
"fixed", a findings-fix step precedes this drive.
Grader follows the evidence ladder (code, parsed
events, raw log only on discrepancy). Hardening:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(required Muse integration drive).
