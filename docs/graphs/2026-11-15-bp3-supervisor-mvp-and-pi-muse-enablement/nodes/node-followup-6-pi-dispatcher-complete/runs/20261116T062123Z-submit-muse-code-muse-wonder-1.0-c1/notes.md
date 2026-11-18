# followup.6 author notes (c1)

Completed dogfood.2's dispatcher in `extensions/bp3-pi/`:

- Roles: `src/roles.ts` parses role files (`roles/author|reviewer|checker|lander.md`,
  frontmatter `model`/`thinking`/`tools`). Effective config is override > role >
  conductor (`BP3_MODEL`/`BP3_THINKING`), landed in child env, pi argv
  (`--model`/`--thinking`/`--tools`), and the InitRecord. Unknown role refuses
  `E_NOT_FOUND`; a child never silently inherits when a role names a model.
- InitRecord thinking: `bp3 harness record-init` gained `--thinking`
  (`src/quest/harness.ml`, help swept) so role routing is gradeable from the
  record bp3 writes, not from env folklore.
- await: `await_runs` was already a thin `bp3 harness watch` relay; kept verbatim.
  Proved: settled on finished Run; hung child -> watch TERM/KILLs alone ->
  `watchdog_killed`/`orphaned`, never `finished`; closed-not-exited suspends the
  silence kill while the timeout still applies. Property test: no signal call
  exists in `dispatcher.ts` (watch is the sole killer).
- release: `release_desk` relays `bp3 harness desk release`; dirty desk refused
  and preserved, clean desk released, release always explicit.
- Fake-pi suite now covers clean / hung / closed-not-exited / crash /
  malformed / self-settled kinds. Malformed and self-settled tapes never derive
  `finished`; crash refuses the bind (`E_TAPE_BIND`).

Verification observed: `node --test extensions/bp3-pi/test/` 11/11 pass;
`./test/harness.sh` all checks passed; `dune build src/quest/main.exe` clean.
One real-pi drive per the clean case class: `spawn_run(role=author)` with real
`pi` -> InitRecord model `openai/gpt-6.1-sol`/thinking `medium`,
`list_runs` = `finished`, `await_runs` = settled/finished (observed in session,
tape in this folder). Hung/silent real-pi drives were not run; those case
classes are proved on fake-pi + the OCaml watch suite, not synthetic-only for
the mechanism (watch itself is OCaml, exercised by `test/harness.sh`).

Lesson: zombie pids fool `kill(pid, 0)` in the test parent; assert the exit
signal instead. `list_runs` on cache-missing failure-kind Runs pays watch's 5s
fallback per Run — the suite's 25s tail is that honesty, not a hang.
