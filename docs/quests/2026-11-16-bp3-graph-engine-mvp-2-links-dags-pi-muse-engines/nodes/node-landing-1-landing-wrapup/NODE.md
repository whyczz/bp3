---
date: 2026-11-16
goal: ../QUEST.md
exp: landing.1
status: proposed
---

# landing.1 - landing-wrapup: honest close with clocks

## TL;DR

Close the graph-engine graph: scorecard including
per-node wall/wait/dwell and ready-set timings,
findings 100% dispositioned with homes, and the
landing walkthrough actually run
(red-ink-goal-landing-demo diligence) for the
owner's promotion review.

## Demo (design trace)

```text
traces + findings ─► disposition ─► scorecard (timed) ─► walkthrough (run)
```

## Diagram

```text
all nodes' artifacts ─► scorecard + disposition ─► owner gate
```

## Pseudocode

```python
wrap = {scorecard(nodes, timing=True), disposition(findings), run_walkthrough()}
```

| Field | Value |
|---|---|
| Intent | nothing learned gets lost; speed claims judged on system numbers |
| Lane | standard |
| Output | wrap-up record + walkthrough package |
| Depends on | rename.1, followup.3, dogfood.3 (owner sequencing 2026-11-17) |

## Acceptance

| Case | Expected |
|---|---|
| scorecard complete | every node present with observed evidence; wall/wait/dwell from the system (post-rename surfaces), unmeasured fields named with reasons |
| findings dispositioned | 100% of graph findings fixed / iceboxed / rejected with homes; nothing "fixed" without a fix step |
| walkthrough run | executed, outputs quoted; A/B and ready-set results presented from dogfood numbers |
| diagrams included | generated ascii + mermaid of the final graph state attached from the live rollup |

## Acceptance test (goal block)

- **Objective:** the graph can land honestly,
  speed story included.
- **Prove by:** this record + the observed
  walkthrough.
- **Done when:** owner walkthrough held with
  artifacts and timings in hand.

## Tests

Completeness: every node in the scorecard with
an evidence link or explicit unmeasured; every
finding dispositioned. Property: no number
without a source artifact.

## Context

Per graph law, landing runs
red-ink-goal-landing-demo diligence before
promotion; this exp stages and runs its inputs.
