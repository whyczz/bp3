# Run notes — exp-landing-1-landing-wrapup c1 (muse-code)

## What was built

- `scorecard.md`: all 18 exps with ledger state, bound commit, and
  observed evidence; three named unmeasured exceptions with reasons.
- `disposition.md`: all 729 (backtest.1) + 43 (backtest.2) findings
  dispositioned in nine buckets — fixed only where a landed exp
  implemented the mechanism (followup.2, mvp.8/dogfood.3), rejected
  where the fold was honestly right, two deliberately-open icebox rows.
- `walkthrough.md`: the `quest_fin` demo input, executed in this Run
  (ledger + `init-check` live; outputs in `tape.log`), not scheduled.

## Lessons

- The muse `backtest` replay is heavy (2000+ tapes); landing cites
  the landed runs' committed `backtest.json`/`findings.md` instead of
  re-replaying the corpus. A partial live re-run was stopped; the
  tape keeps what it emitted verbatim.
- `init-check --engine pi` is blind on this host: the probed source
  `/Users/whycz/.pi/sessions` is absent while real pi tapes live
  under `/Users/whycz/.pi/agent/sessions`. Recorded as disposition
  D8 — warn-only by design, alignment deferred to the owner.
- `find-tape` for the dogfood.3 pi Run returned `E_NOT_FOUND` from
  this desk for the same path reason; the committed
  `pi-derivation.json` remains the observed `finished` evidence.
- No code changed in this Run: landing is a record, and claiming
  code fixes here would violate the exp's own "fixed" rule.
