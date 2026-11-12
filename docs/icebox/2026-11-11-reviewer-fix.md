---
status: frozen
date: 2026-11-11
promoted: null
---

# Reviewer may fix (fresh review required)

## Context

Frozen during the red-ink walk of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/QUEST.red-ink.md)
(working copy; the original Quest is untouched). The settled
FSM sends a `needs_fix` verdict back to `todo` (`cycle + 1`,
or `blocked` at `max_cycles`), and the next commit arrives via
`submit`. We settled the direction — the reviewing Run may
produce the fix commit, but must never review its own fix —
and then deliberately deferred it: **MVP reviewers judge
only; fix commits come from author Runs.** This entry is the
future quest that lifts that restriction.

Why it is attractive: the reviewer holds the freshest context
on exactly what is wrong. Routing the fix through a separate
author Run re-buys that context — the rent this whole design
exists to stop paying.

## Sketch

No new state, no new edge. After `needs_fix` returns the exp
to `todo`, the engine may dispatch the fix work to the same
Run that reviewed (warm/fork context), which commits and
takes the existing `submit` edge. The binary gains one guard:

- A `review` of commit X is refused with `E_SELF_REVIEW`
  (facts: submitting run, reviewing run; guidance: dispatch a
  fresh reviewer) when the reviewing Run is the Run that
  submitted X.
- Fresh means a different Run. Same harness, same model,
  different Run is acceptable — independence of context, not
  of brand.
- Ledger lines therefore carry run identity on `submit` and
  `review` (harness/model alone cannot distinguish two Runs).

The engine skill gains the dispatch pattern: review Run
fixes → fresh review Run judges. `exp_type` may grow a knob
(e.g. `review.fix: allowed | authors_only`) only if a second
profile actually needs the restriction.

## Blockers

- **Run identity in the ledger.** Today run identity lives in
  the tape path (`runs/<id>/`), not as a ledger field. The
  guard needs the submitting Run recorded on the `submit`
  line and the reviewing Run on the `review` line.
- **What counts as “the same Run.”** Needs one definition
  across engines (workflow subagent, pane worker, single
  session) before the guard can be judged identically.
- **Cycle accounting.** A reviewer fix followed by another
  `needs_fix` must consume cycles exactly like an author fix
  — no free loops because the fixer wore a reviewer hat.
- **Skill sync.** The engine/using-bp3 successor skill must
  teach the fix-then-fresh-review dispatch, and Terms in the
  MVP quest must stop implying reviewers never touch code.
- **Tests that fail today.** Self-review of a self-submitted
  commit is currently indistinguishable from a fresh review;
  fixtures need: self-review refused, fresh review accepted,
  same-model/different-Run review accepted.

## Promotion trigger

Thaw when the MVP engine is running real exps and the
author-bounce cost shows up in the scorecard (rework cycles
dominated by context re-load, not by disagreement). Not
before the core FSM lands — this is an optimization of a
loop that must first exist.
