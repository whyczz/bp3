# Run notes — exp-dogfood-2-pi-supervisor-rethink c2 (design)

## What changed

- Recorded the owner nod in EXPERIMENT.md: the owner
  approved the design as decided (keep dispatcher,
  engine contract, roles, run-id, desks; replace
  settled/binding/await with InitRecord + bind-tape +
  `watch` as sole killer; drop witness writer, events
  store, TS fold, second watchdog, heartbeat). The
  cycle 2 `resume` ledger line carries the ruling;
  TL;DR, Acceptance, Owner gate, diagram, and
  pseudocode now agree.

## Lessons

- A gated `missing` grade is the system working: c1
  failed only on the unrecorded nod, and the fix was
  to record the decision, not to soften the gate.
- Design-exps still need a clean tree to submit:
  unrelated tape appends blocked c1's first attempt;
  restoring them (not committing them) keeps the
  bound commit scoped to this exp.

## Verification

- Fresh extract of dogfood.3 flappy.html module
  script (5225 bytes) + `node --check` exit 0,
  matching the c1 grader's rung-3 evidence.
- Design completeness re-read: keep/replace/drop
  table, 8 settled defects, and backtest.2 F1–F4
  unchanged and still dispositioned; no code changed,
  so no test suite run — stated, not implied.
