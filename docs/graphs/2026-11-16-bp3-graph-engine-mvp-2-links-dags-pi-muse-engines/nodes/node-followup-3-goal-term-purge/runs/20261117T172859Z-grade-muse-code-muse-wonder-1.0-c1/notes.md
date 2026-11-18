# Grade notes — exp-followup-3-goal-term-purge c1

- Verdict: fix_first (maps to needs_fix). Decided at rungs 2–3; no whole-tape (rung 5b) read, no 5a pointer needed.
- Critical: grep proof fails. `git grep -i -w quest c0ab195 -- docs/goals/ (excl runs/ledger/this EXPERIMENT.md)` returns 671 lines, exit 0. First hit matches matrix quote: `docs/goals/2026-11-05-bp3-mvp/GOAL.md:11: scheduling, and survives the Controller dying mid-flight. When this Quest`. That GOAL.md is a live renamed surface, not landed ledger text nor this record's history quote, so no named exemption covers it.
- Code rename itself looks sound: store.ml goal paths/branch with one-place legacy fold for `bp3/quest/` and `quest_type`, main.ml GOAL.md/goal_type; naming skill line synced. Conduct read returns handed_off at bound commit.
- Scope-C amendment (GRAPH.md/NODE.md, traverse, migration script) was added after c0ab195 (diff c0ab..HEAD on EXPERIMENT.md), so it is not gated at the bound commit.
- Lesson: a rename that moves files without purging their prose cannot claim grep-zero; the acceptance grep scope must be run verbatim, not sampled.
- make check re-run in this grade exceeded the wait and was terminated; verdict already decided by the gated grep-proof fail, so it cannot flip the outcome. Matrix rung-3 make-check was pass at handoff.
