# bp3-pi

Pi extension + dispatcher implementing dogfood.2's pi MVP,
components A+B (spawn path): a fail-open extension with
exactly four conductor tools, backed by a dispatcher that
spawns pi children under the supervisor.

- `index.ts` — component A. Registers `spawn_run`,
  `await_runs`, `list_runs`, `release_desk` and nothing
  more. Loading never throws; with `bp3` unreachable the
  session still works and the tools refuse with a typed
  error. It mints/parses no run-ids, derives no lifecycle,
  writes no proof, kills nothing, spawns no grandchildren.
- `src/contract.ts` — `SpawnInput`, the `E_REFUSED_INPUT`
  hostile-key refusal (names the key: `BP3_DECIDER`, caller
  `env`/`tools`, caller run-id), and the run-id mint
  (`<ts>-<edge>-pi-<model>-c<cycle>`).
- `src/dispatcher.ts` — component B, spawn + handoff only.
  `spawn_run`: validate, mint, spawn one pi child with
  `BP3_RUN_ID`/`BP3_MODEL`/`BP3_THINKING` in env, call
  `bp3 harness record-init` with the live pid before work,
  then `bp3 harness bind-tape` after exit (1 tape <> 1
  run-id). Repo root resolves via git common dir, so a
  nested subdir binds the same quest as the root.
  `await_runs` relays `bp3 harness watch` verbatim (watch
  is the sole killer); `list_runs` relays the supervisor's
  derived lifecycle from `run-lifecycle-derivations/`;
  `release_desk` relays `bp3 harness desk release`.
  The dispatcher writes nothing under
  `run-lifecycle-derivations/`; bp3 is the only writer.

Await/release/roles completion is followup.6.

## Test

```sh
node --test extensions/bp3-pi/test/bp3-pi.test.mjs
```

Fake-pi + real-bp3 suite: load/fail-open, four-tool
surface, hostile refusals by key name, spawn trivial
child -> `finished`, nested-subdir spawn -> same quest,
and the no-proof-writing property (only bp3 artifacts
appear under `run-lifecycle-derivations/`).
