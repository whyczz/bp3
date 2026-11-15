---
status: frozen
date: 2026-11-15
promoted: null
---

# Grade on a different model than build

## Context

TODO frozen from the bp3-workflows-v2 red-ink walk
(2026-11-15), where the owner ruled it out of that
quest's scope. The question: may `induct-grade` children
run under a different model (or effort) than the build
children — a stronger judge, or a cheaper one — instead
of inheriting the launching session's model?

Today every workflow child inherits the parent session's
model; per-call model routing in the workflow host API
exists in the tool spec but is unprobed on this build
for our saved workflows.

## Sketch

- Probe: one `induct-grade` run with an explicit
  per-child model override on the audit child only;
  record in the Run's ledger/notes which model actually
  served (identity env / hook `usage_recorded` lines are
  the evidence, not the config's claim).
- If routing works: a quest-level knob
  (`grade_model` in workflow args; build stays default),
  conductor passes it only to the grade step.
- If routing silently ignores the override, record that
  as the answer and delete the knob idea.

## Blockers

- Unverified whether the saved-workflow host honors
  per-call `model` for `host.agent` children here.
- No cost/quality data yet comparing same-model vs
  split-model grading on our exps; without it the knob
  is decoration.

## Promotion trigger

Thaw when a grade visibly rubber-stamps (a landed exp a
human later finds wanting) or when grade cost dominates
a quest scorecard — either direction argues for routing
the judge differently from the builder.
