# followup.3 cycle-4 handoff — notes

- The migration renamed every node folder but never re-pointed the
  graph's own index: all 18 `[record]` links in GRAPH.md still used
  the pre-migration `experiments/exp-*/NODE.md` spelling. One
  mechanical sweep (`experiments/exp-` -> `nodes/node-`) fixed the
  named link and the 17 same-class links; every target verified to
  exist on disk before hand-off.
- AGENTS.md is a live surface too: its Layout block and status
  sentence still documented `GOAL.md` two cycles after the file
  became `GRAPH.md`. Renames must grep the repo guide, not only the
  renamed tree.
- Scope discipline held: GRAPH.md prose still carries older
  spellings (e.g. the `exp-<...>` naming note). Left untouched —
  the fix was links and the AGENTS term only, exactly as graded.
