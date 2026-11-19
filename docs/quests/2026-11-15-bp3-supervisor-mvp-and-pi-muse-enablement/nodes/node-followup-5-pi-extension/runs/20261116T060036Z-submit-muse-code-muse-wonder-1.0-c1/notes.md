# Run notes — exp-followup-5-pi-extension c1 (muse author)

## What was built

- `extensions/bp3-pi/` (dogfood.2 components A+B, spawn
  path): fail-open `index.ts` registering exactly four
  conductor tools (`spawn_run`, `await_runs`, `list_runs`,
  `release_desk`); `src/contract.ts` (`SpawnInput`,
  `E_REFUSED_INPUT` naming the key, run-id mint);
  `src/dispatcher.ts` (validate -> mint -> spawn one pi
  child -> `record-init` with live pid -> `bind-tape`
  after exit; `await_runs`/`list_runs`/`release_desk`
  relay watch/derived-cache/desk-release verbatim).
  No witness writer, no events store, no TS fold, no
  second watchdog; the dispatcher writes nothing under
  `run-lifecycle-derivations/` — bp3 is the only writer.
- Committed suite `extensions/bp3-pi/test/bp3-pi.test.mjs`
  (fake-pi + real-bp3 fold), wired into `make check`.

## Proof observed

- Suite: 4/4 pass; `make check` exit 0 (all gates).
- Real-pi smoke: `pi -e extensions/bp3-pi/index.ts -p
  "Reply with exactly: ok"` in /tmp (non-bp3 dir) printed
  `ok`, exit 0 — extension loads fail-open.
- Real supervised spawn (throwaway /tmp drive, real pi
  gpt-6.1-sol, nested subdir cwd): run
  `20261116T060427Z-submit-pi-gpt-6-1-sol-c1`, pid 51401,
  InitRecord + tape_binding rows only, `list_runs` ->
  `finished` folded by the supervisor.

## Lessons / findings

- bp3 resolves its derivation store from `BP3_ROOT`
  (shim-pinned to the bp3 repo) or cwd for the raw binary;
  the suite therefore drives `_build/default/src/quest/
  main.exe` in a temp repo, while production calls go
  through `bin/bp3` in the bp3 repo itself. A first test
  run polluted the real store via the shim; cleaned up.
- `node --test <dir>` fails on this node (treated as a
  module path); name the test file explicitly.
- record-init is called synchronously right after spawn
  returns the pid; real pi writes its tape header after
  startup, so the InitRecord lands first in practice
  (same-second timestamps observed). The guarantee the
  code makes is: live pid named, before observed work.
- Await/release/roles completion stays followup.6; here
  they are thin verbatim relays, not a second fold/killer.
