---
date: 2026-11-16
goal: ../GRAPH.md
exp: landing.2
status: proposed
---

# landing.2 - landing-wrapup-2: pi extension scorecard and disposition

## TL;DR

Close the pi-extension arc: updated scorecard
(followup.5, followup.6, dogfood.4 with evidence),
new findings dispositioned with homes, and the
landing walkthrough actually run for the owner's
`goal_fin` review.

## Demo (design trace)

```text
traces + findings ─► disposition table ─► scorecard ─► walkthrough (run)
```

## Diagram

```text
followup.5/.6 + dogfood.4 artifacts ─► scorecard delta ─► owner walkthrough
```

## Pseudocode

```python
wrap = {scorecard_delta(traces), disposition(new_findings), run_walkthrough()}
```

| Field | Value |
|---|---|
| Intent | honest close-out of the pi-extension arc; nothing learned gets lost |
| Lane | standard |
| Output | wrap-up record + walkthrough package |
| Depends on | dogfood.4 |

## Acceptance

| Case | Expected |
|---|---|
| scorecard | every new exp present with observed evidence or a named `unmeasured` with reason |
| findings | 100% of new findings dispositioned (fixed / iceboxed / rejected, each with a home); nothing called "fixed" without a fix step |
| walkthrough | run, not merely scheduled; outputs quoted from the run |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the quest can land honestly,
  pi extension included.
- **Prove by:** this record + the observed
  walkthrough.
- **Done when:** owner walkthrough held with
  artifacts in hand.

## Tests

Completeness is the test: every exp in the quest
appears in the scorecard with an observed evidence
link or an explicit unmeasured; every finding has a
disposition. Property-based: no number in the
scorecard lacks a source artifact. Demos: the
walkthrough itself, run.

## Context

Per quest law, landing runs
`red-ink-goal-landing-demo` diligence before
`goal_fin`; this exp stages and runs its inputs.
