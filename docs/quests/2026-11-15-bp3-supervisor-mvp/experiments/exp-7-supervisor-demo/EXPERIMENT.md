---
date: 2026-11-15
quest: ../QUEST.md
exp: 7
status: proposed
---

# Exp 7 — supervisor-demo: the whole animal, observed

## TL;DR

One drive through a toy quest exercising every
supervisor claim: clean Run settles, hung Run is
watchdog-killed and derives orphaned, blind-log Run
warns `W_SENTINEL_BLIND` and still lands under the
split gate. Feeds the quest landing demo.

## Demo (design trace)

```text
toy drive: 3 Runs in parallel
  A clean   -> settled            (fold: close+exit0)
  B hung    -> TERM/KILL 601s     (fold: orphaned)
  C blind   -> W_SENTINEL_BLIND   (pid-derived, lands w/ warning)
bp3 q r: lifecycle column derived, inbox empty
```

## Diagram

```text
toy quest ──► sentinel ──► A settled ─┐
                        ├─► B orphaned ├─► grade (split gate) ─► land
                        └─► C warned ──┘
```

## Pseudocode

```python
drive(toy_quest)         # via induct, unmodified
assert lifecycle == {A: settled, B: orphaned, C: settled_blind}
```

| Field | Value |
|---|---|
| Intent | quest-level functional/E2E evidence for Exps 1-6 together |
| Lane | standard |
| Output | drive record + traces under this exp's runs; landing-demo input |
| Depends on | Exp 1-6 |

## Acceptance (fails today: no supervisor exists to demo)

| Case | Expected |
|---|---|
| full drive | all three Runs derive as tabled; toy exp lands |
| report honesty | warnings appear in scorecard, none hidden |
| no babysitting | conductor context shows zero poll loops (await calls only) |

## Acceptance test (goal block)

- **Objective:** the supervisor supervises a real
  drive end to end.
- **Prove by:** the drive itself; traces quoted.
- **Done when:** toy at exp_fin with the three
  lifecycles observed.

## Tests

quest-level functional/E2E (this exp is the test).
property-based: none. Demos: the drive, observed —
this record's reason to exist.

## Context

Quest-level demo law: prove by observed drive, not
by design trace. Anything red here routes back as a
needs_fix to the owning exp, not a patch here.
