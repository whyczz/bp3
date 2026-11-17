# mig.1 handoff-verbs — land run notes

## Land

- Exp `exp-mig-1-handoff-verbs` read as `approved` at cycle 1
  before landing, commit
  `44196725860125de048415ff6a4be350a90c033b`, legal edges
  `land|block|delete`.
- This run folder did not pre-exist; created fresh for
  run `20261116T194825Z-land-muse-code-muse-wonder-1.0-c1`
  and session output teed to its `tape.log`.
- Landing is the serial merge step for the verified
  handoff/grade/verify rename; no code changes were
  authored in this land run — the landed commit is the
  already-graded and verified exp commit above.
- Lesson: check the concrete run folder before creating
  it and fail on collision (`E_RUN_EXISTS`) rather than
  reusing a prior run's evidence.
