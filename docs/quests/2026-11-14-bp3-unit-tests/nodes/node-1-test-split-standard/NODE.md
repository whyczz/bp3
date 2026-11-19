---
date: 2026-11-14
goal: ../QUEST.md
exp: 1
status: proposed
---

# Exp 1 — Test-split standard in /quest

## TL;DR

The `quest` skill learns to ask for tests the way it
already asks for acceptance: at framing, every exp declares
its **test split** — unit cases, fixtures, demos — and the
exp record tables gain a `Tests` line. An exp may declare
no unit tests, but only as a one-line justified decision.

Inside the unit lane, every exp proposes **both** kinds
(owner, 2026-11-14): **known cases** (named examples —
boundaries, goldens, exact shapes; fast to run, fast to
read when red) and **property-based** cases (a law plus a
generator; breadth over the combinatorial space). Either
kind may be omitted, again only as a stated one-liner —
"no laws: no invariant exists here" is a decision,
silence is not.

Placement (owner, 2026-11-14): per experiment, the tests
come **after everything, at the end** of the record —
after prose. Tests are the exp's closing evidence, not
part of its pitch. (The `red-ink` exp shape already
carries this order; this exp aligns `/quest` with it.)

## Demo (design trace)

An exp framed after this lands carries, next to its
Acceptance block:

```text
| Tests | unit: stale-gate boundary (899/901s), round-trip law ·
          fixtures: test/hooks.sh sweep cases ·
          demos: ledger grep trace (Demo 3 above) |
```

...or, legitimately:

```text
| Tests | unit: none (docs-only exp; no seam) ·
          fixtures: skills render check · demos: none |
```

## Shape

```python
def frame_exp(intent):
    exp = break_down(intent, acceptance="fails today")
    exp.tests = declare_split(
        unit=named_cases_or_justified_none(),
        fixtures=[...], demos=[...])
    return exp

# unit cases fail today too, unless labeled characterization
```

| Field | Value |
|---|---|
| Intent | make "which tests?" a framing question, answered before build |
| Lane | standard |
| Output | `skills/quest/SKILL.md` step + exp-shape `Tests` line; installed copies regenerated |
| Depends on | none |

## Acceptance (fails today)

| Case | Expected |
|---|---|
| `/quest` skill text | no mention of test split (grep) — today: absent |
| exp record shape | tables have no `Tests` field — today: absent |
| this exp's record | carries a `Tests` line — this file, on adoption |

## Acceptance test (goal block)

- **Objective:** the test split is asked for at framing
  and visible in every exp record.
- **Prove by:** grep the skill for the split language;
  read one newly framed exp record; `make check` green.
- **Done when:** skill text + exp shape carry it and
  `test/skills.sh` asserts the key phrases.

## Context

Born at the MVP landing: the owner asked where the unit
tests were, and the answer was "there are none, and
nothing in our process ever asked." The Exp 4 post-mortem
had already shown the pattern — diligence questions added
after a failure (quest step 6.5 exists because Exp 4
shipped unsettled). This is the same move, one level down.

## Tests

unit: none (skill prose; no seam) · fixtures: `test/skills.sh` assertions on the new text · demos: this exp's own record carrying a `Tests` line (dogfood)
