# exp-dogfood-2-parallel-drive — handoff run notes (cycle 2)

- Name chosen: bubble drive inside `test/dogfood-parallel.sh`,
  reusing the repo words `bubble` (terminal bubble, mvp.5),
  `seeded` (the acceptance's seeded node), and `sibling`
  (blocked-sibling isolation). No new file name was coined;
  the proof rides the exp's own drive, as cycle 1's grade
  required coverage in this exp, not elsewhere.
- Fix at the root of the cycle-1 grade: the two gated rows
  (`Pi tree death + revival`, `Muse parity bubble`) had no
  artifact in this exp. The drive now seeds one node per
  engine form in a parallel ready-set:
  - Pi (`bubpi`): real node/edge OS processes claiming real
    links in parallel with a sibling. Edge worker returns a
    typed `E_DECISION` failure and dies; node worker calls
    `block` once, emits exactly one facts-only bubble, exits.
    Death is checked on the process table (`kill(pid, 0)`),
    not inferred from state. After `BP3_DECIDER=human resume`,
    a fresh Pi tree (new run-id, new pid) drives the node to
    `handed_off`; the sibling stays `handed_off` throughout.
  - Muse (`bubcl`): the real `induct-node` workflow run in
    parallel for seeded + sibling nodes against real bp3.
    Seeded returns the same terminal `blocked` bubble
    (reason verbatim, `last_edge: handoff`, one block, failed
    edge never retried) and exits; sibling lands. Revival is
    a second workflow invocation with disjoint run-ids; the
    old host's agent-call count is frozen, proving no old
    agent is resumed.
- Two papercuts found while driving: claims write
  `.bp3-context.json` at the desk root, so Pi handoffs from
  the repo tripped `E_DIRTY_TREE` (fixed in-fixture by
  ignoring that file, as `test/pi-tree.test.mjs` does); and
  workflow briefs carry backticked desk paths before the
  `Run exactly` command, so command extraction must anchor
  on `Run exactly`, not the first backtick pair.
- Observed on the passing drive: ready wall 3982 ms vs
  serial sum 6970 ms; bubble scorecard
  `pi_bubble: blocked, claude_bubble: blocked,
  claude_fresh: landed, sibling_claude: landed`.
  Tokens stay `null` with the cycle-1 named cause.
