# exp-7-live-hooks submit run (cycle 1) — lessons

- Author steps 1-2 done honestly: `.muse/hooks.json` names
  `./bin/bp3 q hooks` for all nine events, and the emitter
  answers a piped payload. But no host hook fired in this
  workflow-child session: registry `{"sessions":{}}`, ledger
  event grep 0, `run_started` absent for this run_id.
- The witness gate in `src/quest/hooks.ml` (PreToolUse +
  env preset + run folder on disk) is satisfiable and was
  satisfied; the missing link is host-side invocation, not
  delivery or emitter logic. Do not hand-invoke `bp3 q hooks`
  with the real run_id to fake the line — that is exactly
  the evidence this exp exists to produce organically.
- Tape gap: the first shell command's `tee -a` raced the
  run-folder `mkdir` in the same pipeline and failed, so
  early commands are not in tape.log; teeing started once
  the folder existed. Tape stays verbatim; nothing was
  reconstructed into it.
- `bp3 q u submit` refuses a dirty tree (`status --porcelain`
  non-empty), so the three untracked exp-6 cycle-2 run
  folders left by earlier Runs were committed first as
  their own tape commit, keeping this Run's bound commit
  to exp-7 files only.
