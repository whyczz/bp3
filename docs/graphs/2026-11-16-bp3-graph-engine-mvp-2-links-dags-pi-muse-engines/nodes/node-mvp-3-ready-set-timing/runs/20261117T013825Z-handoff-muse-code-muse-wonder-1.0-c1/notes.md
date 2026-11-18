# exp-mvp-3-ready-set-timing — author run notes

- Naming (code-writer + /naming): reused the quest's settled
  words — `dep` for node deps, `ready` / `ready_set_waves` /
  `starved` for the schedule, `wall_s` / `wait_s` / `dwell_s`
  and `setup_wall_s` for timing. One spelling everywhere:
  code, rollup JSON, tests, and the traverse skill.
- Node deps live in exp ledger records: `--depends-on` at
  `bp3 q <quest> c <exp>`, redeclared by the new dep verb
  `bp3 q <quest> dep <exp> --depends-on <a,b> --reason <why>`.
  A cycle refuses at write time with `E_DEP_CYCLE` naming the
  cycle; unknown deps refuse `E_NOT_FOUND`. Handoff also
  refuses `E_DEPENDENCY` while node deps are unlanded.
- Ready-set waves are BFS layers over `todo` nodes whose deps
  are landed (or in earlier layers); `ready` is the first
  wave. A `blocked` node names its transitive `todo`
  dependents in `starved`; independent nodes stay ready.
- Timing is derived on read from ledger timestamps only
  (wall = first handoff → land, wait = create → first
  handoff, dwell per state, cycles from the fold). Nothing
  is written to any committed file; reads leave tips and
  the worktree untouched (asserted in test/ready.sh).
- Setup per Run is mint → claim (`setup_wall_s`) from
  machine-local run configs on the rollup; over the local
  `setup_slow_s` threshold (default 180) the rollup warns
  `W_SETUP_SLOW`, locally only — never in a ledger.
- Dep-freeze exploration: deps stay mutable-but-logged.
  The one schedule anomaly exercised is a deliberate
  mid-flight dep edit (state `handed_off`, cycle 1): the
  `dep` ledger line records state, cycle, and the new deps,
  and the node's state does not move. No anomaly was
  observed from accidental edits in the fixtures. Proposed
  rule from this evidence: keep deps mutable while `todo`;
  once a node leaves `todo`, a dep edit should require the
  reason to name the schedule change (as the test does) —
  a hard freeze is not justified yet; revisit if dogfood.2
  shows a real mid-flight surprise.
- `induct-node` (skills/traverse/workflows/induct-node.js,
  installed copy in .agents/workflows) owns one node's FSM
  loop in one workflow run — author, grade+verify, land as
  phases — and returns exactly one terminal outcome
  (`landed`, `blocked`, `deleted`). The Pi form of the same
  contract is stated in its header: root session spawns one
  node-worker session per ready node, which claims its node
  link and loops `spawn_run` per edge. Landing stays serial
  at the root; bp3's land already re-checks mergeability
  against the new tip (serial fixture in test/ready.sh).
- Verification: `test/ready.sh` (deps/cycle/waves/starved/
  timing/setup/serial-land/help), `test/induct-node.test.mjs`
  via test/traverse.sh, and the full `make check` gate.
  Pre-existing dirty `.agents/workflows` renders (install
  copies of already-committed mvp.1/mvp.2 workflow sources)
  were committed separately so the handoff tree is clean.
