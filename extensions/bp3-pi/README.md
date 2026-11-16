# bp3-pi

Pi extension + dispatcher implementing dogfood.2's pi MVP,
components A+B: a fail-open extension with exactly four
conductor tools, backed by a dispatcher that spawns pi
children under the supervisor. followup.6 completes the
dispatcher: await, release, and roles.

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
- `src/roles.ts` + `roles/*.md` — role files (`author`,
  `reviewer`, `checker`, `lander`) whose frontmatter
  `model`/`thinking`/`tools` route the child. Precedence:
  spawn override beats role, role beats the conductor's
  `BP3_MODEL`/`BP3_THINKING`. Effective values land in the
  child env (`BP3_MODEL`/`BP3_THINKING`), the pi argv
  (`--model`/`--thinking`/`--tools`), and the InitRecord.
- `src/dispatcher.ts` — component B, spawn + handoff only.
  `spawn_run`: validate, load role, mint, spawn one pi
  child with `BP3_RUN_ID`/`BP3_MODEL`/`BP3_THINKING` in
  env, call `bp3 harness record-init` with the live pid
  (plus effective model/thinking) before work, then
  `bp3 harness bind-tape` after exit (1 tape <> 1
  run-id). Repo root resolves via git common dir, so a
  nested subdir binds the same quest as the root.
  `await_runs` is a thin relay over `bp3 harness watch` —
  watch's verdict verbatim (settled / watchdog_killed /
  timeout), no polling loop, no second watchdog, no
  lifecycle fold, and the dispatcher never signals a pid:
  watch is the sole killer. A hung child lands `orphaned`,
  never `finished`; a closed-not-exited child suspends the
  silence kill while the overall timeout still applies.
  `list_runs` relays the supervisor's derived lifecycle
  from `run-lifecycle-derivations/`; `release_desk` relays
  `bp3 harness desk release` (a dirty desk is refused and
  preserved; release is always explicit). The dispatcher
  writes nothing under `run-lifecycle-derivations/`; bp3
  is the only writer.

## Test

```sh
node --test extensions/bp3-pi/test/bp3-pi.test.mjs
```

Fake-pi + real-bp3 suite: load/fail-open, four-tool
surface, hostile refusals by key name, spawn trivial
child -> `finished`, nested-subdir spawn -> same quest,
role routing (override > role > conductor) observed in
child env + InitRecord, await verbatim on a finished Run,
hung child killed by watch alone -> `orphaned`,
closed-not-exited -> silence kill suspended, timeout
applies, crash/malformed/self-settled tapes never finish,
dirty desk refused / clean desk released, the
no-proof-writing property, and the sole-killer property
(no signal call in the dispatcher).
