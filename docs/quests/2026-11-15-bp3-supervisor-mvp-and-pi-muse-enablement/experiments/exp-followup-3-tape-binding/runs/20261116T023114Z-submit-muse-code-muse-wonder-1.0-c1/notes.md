# followup.3 tape-binding — author notes (c1)

- Added `bp3 harness bind-tape --run-id <id> --tape-path <p>` (alias `t`):
  the launcher's post-spawn bind step. It appends one pointer-only
  `tape_binding` row (run-id, tape path, ts — 4 keys, no tape content)
  via the single-write `append_row`; a run-id with no InitRecord is
  `E_NOT_FOUND`, never a guessed binding.
- Fold honor in `fold_run_file` and `all_init_records`: the effective
  tape is the InitRecord's own path, else the latest binding's. With
  no tape at all the probe is blind (`W_SUPERVISOR_BLIND`) and the
  lifecycle stays `init`. Bound observations carry the tape pointer.
- Tail scan in `tape_evidence` (muse only): whole entries scanned
  from the end, skipping task entries (`payload.kind == "task"`);
  the first non-task entry decides (`session.end` or run terminal).
  A terminal buried under non-task entries finishes nothing; a torn
  final entry (unterminated or unparseable) finishes nothing and
  warns `W_TORN_TAIL`, with or without a binding. Pi still reads
  only its last whole entry. A live pid is never `finished`.
- Launcher: `induct-exp.js` (skills + .agents copies) record-init
  now names no tape; after the author returns it resolves the
  session tape with `find-tape` and binds it with `bind-tape`.
  A refused resolution binds nothing and records a typed refusal;
  the author child writes no InitRecord, binding, or observation.
  Grade/land launchers still record-init without a tape and can
  adopt the same bind step unchanged (same verb, same fold).
- Tests: `test/harness.sh` followup.3 section (help/usage, unbound
  blind init, bound finished + observation pointer + find-tape/watch
  honor, live-pid, mid-tape marker, torn unterminated + unparseable,
  latest-binding-wins) and `test/induct-exp.test.mjs` bind-step cases.
  `make check` green; one transient `worktree.sh` parallel-prepare
  failure under load passed on re-run and standalone.
