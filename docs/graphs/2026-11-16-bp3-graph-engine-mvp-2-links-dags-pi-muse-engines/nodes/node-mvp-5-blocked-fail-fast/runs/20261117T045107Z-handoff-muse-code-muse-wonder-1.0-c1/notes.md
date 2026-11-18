# Run notes — exp-mvp-5-blocked-fail-fast (handoff, cycle 1)

Lessons from this run:

- Most of the fail-fast state law already lived in bp3
  (block/resume, cap escalation, inbox, stale-edge
  refusal). The missing piece was the node worker's
  loop: it retried a failed edge up to the step cap and
  never called block. Classify the child's return
  (verdict cast / typed failure / silent orphan) before
  deciding; only the typed shape blocks, and it blocks
  exactly once with the reason verbatim.
- A blocked bubble is facts, not handles: graph, node,
  state, reason, last edge, run chain, desk, inbox key.
  The root pages and revives from those alone.
- The node read needed its own decision point
  (`blocked: {reason, checkpoint, since}`); the quest
  inbox alone forces a fresh worker to know to look at
  the rollup instead of its own node.
- Mock-host workflow tests carry the process contract
  (one block, no retry, one replacement mint); the
  shell fixture carries the state contract (stale
  refusal names current state, checkpoint only when
  dirty, siblings stay ready). Neither substitutes for
  the other.
- Pi tree-death process proof (real process table,
  unreaped grandchild) stays with the Pi drive; this
  commit lands the Muse terminal-bubble form of the
  same law.
