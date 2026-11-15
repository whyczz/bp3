---
date: 2026-11-15
quest: ../QUEST.md
exp: landing.1
status: proposed
---

# landing.1 - landing-wrapup: scorecard and disposition

## TL;DR

Close the Quest: scorecard from supervisor traces,
backtest findings dispositioned (fixed / iceboxed /
rejected, each with a home), and the landing-demo
input for the owner walkthrough at `quest_fin`.

## Demo (design trace)

```text
findings: 14 -> fixed 9 (mvp.4-mvp.5), iceboxed 3, rejected 2
drives: muse toy landed; pi toy landed; blind/hung cases observed
```

## Diagram

```text
traces + findings ─► disposition table ─► scorecard ─► landing demo
```

## Pseudocode

```python
wrap = {scorecard(traces), disposition(findings), demo_inputs()}
```

| Field | Value |
|---|---|
| Intent | honest close-out; nothing learned gets lost |
| Lane | standard |
| Output | wrap-up record + landing demo package |
| Depends on | dogfood.1, dogfood.3 |

## Acceptance (fails today: quest unstarted)

| Case | Expected |
|---|---|
| scorecard | every field present or "unmeasured" |
| findings | 100% dispositioned with homes |
| demo inputs | walkthrough runnable from the record |

## Acceptance test (goal block)

- **Objective:** the quest can land honestly.
- **Prove by:** this record + demo dry run.
- **Done when:** owner walkthrough scheduled with
  artifacts in hand.

## Tests

wrap-up exp: completeness is the test. Known
cases: every exp appears in the scorecard with an
observed evidence link or an explicit unmeasured;
every backtest finding has a disposition (fixed,
deferred to icebox, dropped with reason).
Property-based: no number in the scorecard lacks a
source artifact. Demos: the landing walkthrough
itself.

## Context

Per quest law, landing runs
`red-ink-quest-landing-demo` diligence before
`quest_fin`; this exp stages its inputs.

## Auto-red-ink addendum

The walkthrough must be run, not merely scheduled.
`unmeasured` scorecard fields are capped at named
exceptions with reasons. No finding may be called
"fixed" unless a findings-fix step implemented it;
otherwise its disposition is iceboxed or rejected
with a home. Hardening evidence: the observed
walkthrough itself.
