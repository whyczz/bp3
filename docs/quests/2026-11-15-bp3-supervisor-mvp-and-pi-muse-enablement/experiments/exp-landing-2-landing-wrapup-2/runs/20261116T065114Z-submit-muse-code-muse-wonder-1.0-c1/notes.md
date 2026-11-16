# Run notes — exp-landing-2-landing-wrapup-2 c1 (muse-code)

## What was built

- `scorecard.md`: the pi-extension arc delta (followup.5,
  followup.6, dogfood.4) with ledger state, bound commits, and
  observed evidence; five named unmeasured exceptions with reasons.
  The landing.1 scorecard (18 exps) stands unchanged beneath it.
- `disposition.md`: every finding the arc raised (P1–P6) with a
  home — fixed only where followup.6 implemented the mechanism,
  two rejected as honestly-bounded, three iceboxed deliberately.
- `walkthrough.md`: the `quest_fin` demo input for the arc,
  executed in this Run (ledger, `init-check` both engines,
  `find-tape`, derivation re-read, fresh test gates), not scheduled.

## Lessons

- `find-tape` for a pi Run refuses `E_NOT_FOUND` from a quest
  worktree desk for the same probed-source path gap that fires
  `W_SUPERVISOR_BLIND` (landing.1 D8). The pi derivation still
  folds `finished` from InitRecord + bound tape; the refusal is
  the lookup door, not the lifecycle. Recorded as P5, not fixed.
- The bp3-pi suite's 25s tail is honest latency (`list_runs`
  paying watch's fallback per cache-missing Run), and its full
  run takes ~31s; budget the landing re-run accordingly.
- No code changed in this Run: landing is a record, and claiming
  code fixes here would violate the exp's own "fixed" rule. The
  three iceboxed items (P4–P6) each name the exp-shaped home a
  real fix would need.
