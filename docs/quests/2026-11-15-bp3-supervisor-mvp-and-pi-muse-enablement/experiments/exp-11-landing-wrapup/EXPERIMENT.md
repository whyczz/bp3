---
date: 2026-11-15
quest: ../QUEST.md
exp: 11
status: proposed
---

# Exp 11 — landing-wrapup: scorecard and disposition

## TL;DR

Close the Quest: scorecard from supervisor traces,
backtest findings dispositioned (fixed / iceboxed /
rejected, each with a home), and the landing-demo
input for the owner walkthrough at `quest_fin`.

## Demo (design trace)

```text
findings: 14 -> fixed 9 (Exps 4-5), iceboxed 3, rejected 2
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
| Depends on | Exp 8, Exp 10 |

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

wrap-up exp: completeness is the test. Demos: the
landing walkthrough itself.

## Context

Per quest law, landing runs
`red-ink-quest-landing-demo` diligence before
`quest_fin`; this exp stages its inputs.
