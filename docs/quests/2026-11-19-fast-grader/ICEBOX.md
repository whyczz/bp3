---
status: frozen
date: 2026-11-19
promoted: null
---

# Fast grader: minutes per grade, not half an hour

## Context

Frozen 2026-11-19 at the end of the test-pyramid run
(`docs/quests/2026-11-18-test-pyramid/`). Owner, verbatim: "bro this
system takes forever, does it catch good bugs?", then "and let's break
the induct loop. we need a faster grader". The owner stopped the
subagent grading loop mid-quest and judged the last two nodes directly.

What the run showed:

- Each grade was a fresh subagent: 7 to 35 minutes of wall time and
  100-200k tokens. tier.1 took 8 rounds, js.1 3, tier.2 3.
- Graders were precise; no finding was wrong. But about half of all
  findings were the author's own test probes that could not fail, or
  commit messages claiming more than was verified. A self-check by the
  author would have caught them in minutes, not a round.
- Full-matrix re-grades were the slow part. A delta brief (verify the
  prior findings, read the diff, run the gate, about a 15-minute cap)
  cut later rounds to 7-15 minutes.
- Related: `2026-11-17-mini-warden-run-budgets.md` (grade under 5 min
  as a budget), `2026-11-19-yolo-decider.md` (`needs_fix_yolo`, fewer
  pages).

## Sketch

Three changes, cheapest first; no engine change.

```text
author: commit -> self-mutate the new checks (plant the bug each guards) -> make check-full
grade:  round 1 = full brief, capped; round 2+ = delta brief, capped
        (prior findings + diff + make check-full, nothing else)
lane:   standard nodes get the fast grade; high-blast-radius nodes keep the deep one
```

- **Author self-mutation before handoff**: the induct skills require
  the author to plant the regression each new check guards and record
  "planted -> red" in the commit's Verification. A claim not seen to
  fail is written as unverified.
- **Delta and time cap by default**: induct-inline and induct-grade
  briefs take the previous verdict's findings and the diff, with a
  stated wall-time cap. The full matrix runs only in round 1.
- **Lane-sized grading**: the node's Lane decides depth: micro and
  standard get the fast brief, high-blast-radius gets the deep one.

Not added: grader result caching, reuse of the author's gate run as
grade evidence (a verdict binds to a run the grader saw), or any
change to who may land.

## Blockers

- **Trust boundary**: how much the grader may take from the author's
  record (mutation notes, timing logs) without re-running it. Today:
  nothing, which is why grades are slow.
- **Cap semantics**: what a grader returns when the cap hits mid-check
  (verdict on what ran, plus "unchecked" rows?). It must never read
  as a pass.
- **Measuring it**: wall time and tokens per grade are in the
  subagent usage lines, not the ledger; the warden audit owns
  that.
- **Skill changes ride as their own node**: induct, induct-inline,
  induct-grade.

## Promotion trigger

The owner frames the next quest that uses the induct loop, or any grade
runs past 15 minutes again.
