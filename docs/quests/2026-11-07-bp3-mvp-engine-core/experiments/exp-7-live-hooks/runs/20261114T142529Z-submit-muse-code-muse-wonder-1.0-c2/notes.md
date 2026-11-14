# Run notes — exp-7-live-hooks submit, cycle 2

Run: `20261114T142529Z-submit-muse-code-muse-wonder-1.0-c2`
Harness/model: muse-code / muse-wonder-1.0. Session
`727f5e85-9ce1-78f7-8436-fddd6139e8ff`.

## Lessons

- Cycle 1's absence was a launch-timing defect, not an
  emitter defect: hooks load at session start, and the
  cycle 1 children predated `.muse/hooks.json`. A fresh
  process in cycle 2 fired `PreToolUse` on the first
  prefixed command and the hook committed `run_started`
  to the exp branch mid-Run.
- Verify live evidence from the ledger on the exp
  branch (`git show <exp-branch>:.../ledger.jsonl`),
  never from prose or tape. Mid-Run the count was 2
  (`run_started` + `lint_checked`); `usage_recorded`
  and `run_settled` only exist after settle.
- Event lines and transitions share one ledger but
  disjoint shapes: events carry `ts` + `run_id` with
  no `edge`/`from`/`to`, and `bp3 q r` folds past
  them unchanged (`todo`, cycle 2).
- Naming: no new identifiers coined; the record reuses
  the ledger's own words (`run_started`,
  `lint_checked`, `run_id`) per code-writer naming
  discipline.
