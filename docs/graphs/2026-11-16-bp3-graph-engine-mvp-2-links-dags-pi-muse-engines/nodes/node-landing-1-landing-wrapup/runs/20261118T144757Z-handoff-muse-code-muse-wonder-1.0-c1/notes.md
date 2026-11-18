# Run notes — node-landing-1-landing-wrapup (handoff, cycle 1)

## What was authored

- `scorecard.md`: all 18 nodes from the live rollup; 4 landed
  with wall/dwell/commit, 14 pre-rename nodes named unmeasured
  with the reason (fold maps old verbs, not renamed node IDs).
- `disposition.md`: 12 findings, each fixed (with fix step),
  iceboxed, or rejected with a home. Coverage is by
  construction: records + run notes + rollup warnings +
  deliberately-open table, each exactly once.
- `walkthrough.md`: executed in this Run — claim, `bp3 e`,
  rollup, ascii + mermaid diagrams, landed-node read; A/B and
  ready-set numbers quoted from dogfood.1/.2's own artifacts.

## Lessons

- The live rollup is the honest surface even when it
  disagrees with run-folder evidence: 14 nodes hold land runs
  yet read `todo`. The scorecard quotes the rollup verbatim
  and names the gap (disposition D7) instead of smoothing it.
- `wait_s`, tokens, and human-active minutes have no meter;
  saying `unmeasured` with a reason is the deliverable, not
  a gap in it.
- No promotion, no graph-status flip, no desk release:
  those are the owner's word at goal_fin.

## Verification

- `make check-fast` — pass (exit 0; 8 suites incl. bp3g and
  check-tiers 14 assertions). Full `make check` not run: the
  record names check-fast for cycles, and this Run changes
  only run-record markdown.
