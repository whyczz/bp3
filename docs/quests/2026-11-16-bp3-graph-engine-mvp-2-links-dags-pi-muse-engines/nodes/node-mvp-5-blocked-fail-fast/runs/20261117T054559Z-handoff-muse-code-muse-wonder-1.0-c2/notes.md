# Run notes — exp-mvp-5-blocked-fail-fast (handoff, cycle 2)

Lessons from this run:

- Cycle 2 owed the five Pi rows real process proof.
  `test/pi-tree.test.mjs` spawns a real root ->
  node-worker -> edge-worker OS process tree over
  real bp3 links: typed edge failure -> node worker
  blocks once -> exactly one facts-only bubble
  (graph, node, state, reason, last edge, run chain,
  desk, inbox key; no pid/handle) -> both worker
  pids verified dead on the process table.
- Revival is a fresh tree: after human `resume`,
  a new node worker with a new run-id, pid, and
  claim drives the node to `handed_off`; no old
  pid/session is reused.
- Unreaped grandchild: node worker dies first;
  root follows `parent_run_id` in the run config,
  `bp3 harness watch` dispositions the descendant
  `orphaned`, and only then is the tree checked
  dead. A root-process-death case revives from
  rollup + inbox alone in a brand-new root process.
- Watch's watched pid is the claim-time bp3 pid,
  so process-table assertions must use the real
  spawned worker pids (scratch-recorded), not
  `claim.pid`. Edge workers that outlive a dead
  parent must exit on parent death; nothing parks.
- Fixture hygiene: link claim writes
  `.bp3-context.json` into the desk; a handoff's
  dirty-tree gate needs it gitignored in fixtures.
