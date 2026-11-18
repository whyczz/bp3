# followup.2 workflow-birth — author notes (cycle 1)

All four birth defects fixed at their owning surfaces:

1. Read desk: `readState()` in all four workflow sources
   (bp3g-node, node-loop, bp3g-grade, bp3g-land) now opens
   with the same deskNote every other child prompt carries,
   and points "above" at it. A read can no longer drift to
   the conductor root's foreign-dialect binary.
2. Context: `context` is parsed in node-loop and bp3g-node
   and threaded verbatim into the first author brief
   (bp3g-node: it seeds the cycle fix; a grade's own named
   fix replaces it later). The bp3g dispatch tables name
   the arg. Silent drop is gone; absent context adds no
   clause.
3. Tape binding: find-tape/watch scan resolution tries the
   claim's session first — the tape owned by exactly the
   session that claimed the Run's link resolves before the
   engine-fsm-edge/start-order rule. Stale, sibling, and
   conductor tapes that merely reference the Run lose
   deterministically; genuine ties still refuse
   E_AMBIGUOUS.
4. Stale renders: `bp3 skills check` compares each desk
   render (.agents/workflows/*.js) byte-for-byte with its
   source (skills/bp3g/workflows/*.js); stale or missing
   refuses E_RENDER_STALE naming render and source. The
   bp3g skill states the rule: check before every dispatch,
   re-render in the desk, never launch stale. Desk renders
   re-installed in this run.

Regression fixtures: desk/context cases in the four
workflow mock tests + conduct skill assertions; a
claim-session find-tape fixture in harness.sh (claimed
session beats an earlier own-edge tape); fresh/stale/
re-rendered cases for `skills check` in skills.sh.

Verified: dune build, test/bp3g.sh (all five suites),
test/harness.sh, test/skills.sh (134 assertions),
shellcheck on touched shell files.
