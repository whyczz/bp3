# exp-6-hooks review — lessons

Verdict: fix_first (recorded as needs_fix)

Claims checked against Exp 4's acceptance (exp-6 has no EXPERIMENT.md of
its own; its acceptance is the hook half of exp-4-tape-hooks):

- Pass, with fixture evidence in test/hooks.sh and a fresh `make check`
  (exit 0: lint, skills 43, q, tape, hooks, induct): garbage/foreign/
  unbound/reentrant fail-open; bound run_started -> run_settled with
  session_id, cycle, ts, no edge/from/to; exactly one summed
  usage_recorded at SessionEnd/SubagentStop; refused and lint_checked;
  fold state unchanged by event lines; `.claude/hooks.json` delivered
  by `bp3 skills install` and asserted in test/skills.sh. Comments in
  hooks.ml agree with the code (edge key dropped so the fold skips
  event lines — deliberate, explained in the submit notes).

Findings:

1. [major] SessionStart sweep marks live Runs unsettled —
   src/quest/hooks.ml:267. Every other unsettled binding gets a
   `run_unsettled` line with no staleness/age check on last_seen_ts.
   A second session starting while a parallel Run is live writes a
   false past-tense fact into its ledger, violating the parallel
   no-cross-talk case. The submit notes admit this sharp edge; the
   fixture avoids it by settling first, and no test covers a
   SessionStart arriving while another Run is live. Fix shape: gate
   the sweep on last-seen age (or equivalent liveness), plus a
   fixture with SessionStart during a live parallel binding.
2. [major] Missing observed evidence: the submit notes state no live
   induct-exp run with hooks firing in a real harness session was
   done, so the live half of Exp 4's prove-by (run one live
   induct-exp, read the exp ledger) has no evidence. Exp-6 also has
   no EXPERIMENT.md; its acceptance had to be reconstructed from
   Exp 4's record.
3. [minor, inference] save_registry (hooks.ml:159) writes through one
   shared `.tmp` path with no locking; concurrent hook processes
   could collide or lose bindings. Not observed; sequential hooks
   are unaffected.

What would change my mind: an age/liveness gate on the sweep with a
live-parallel fixture, and one live induct-exp ledger read showing
the event lines from a real harness session.
