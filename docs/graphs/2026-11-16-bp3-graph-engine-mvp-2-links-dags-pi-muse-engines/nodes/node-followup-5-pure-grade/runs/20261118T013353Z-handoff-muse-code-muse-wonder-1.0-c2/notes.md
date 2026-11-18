# followup.5 pure-grade — handoff fix run notes (cycle 2)

Run: 20261118T013353Z-handoff-muse-code-muse-wonder-1.0-c2
Bound commit graded: 4ab3228527b6f0175bfca3b8f4a78184f01debe5 (needs_fix)

## Fix ledger

- RESOLVED (this handoff): the two stale two-cast consumers in
  test/dogfood-parallel.sh now ride the followup.5 combined cast.
  (1) The Muse bubble host agent() dispatches kind "apply" before
  the bp3link_ token parse: it runs the spawn text's Run-exactly
  combined cast and returns its stdout JSON. (2) author_worker casts
  once (grade --verdict ship --verify-verdict pass --commit <bound>)
  and the quality-floor ledger check requires the single grade line
  carrying verify_verdict pass with zero verify-edge lines.

## What I ran

- Reproduced at HEAD first: ./test/dogfood-parallel.sh exit 1,
  TypeError at bubble-drive.mjs:161 via bp3g-node.js callApply.
- After the fix: ./test/dogfood-parallel.sh exit 0 ("dogfood-parallel
  tests: ok"; bubble scorecard pi/claude blocked, claude fresh
  landed, siblings unaffected).
- make check exit 0 (dogfood-parallel ok inside the full gate).

## Lessons

- A workflow-shape change must be swept against every mock that
  dispatches on spawn text or ledger shape, not only the suite the
  author edited; the crash was a null token match, the stale ledger
  check was the second consumer of the same old contract.
- Run evidence is deliberate only as committed notes.md; tape.log
  stays gitignored residue. Committing the outstanding cycle-1
  (this node) and cycle-4 (followup.3) run notes kept the tree
  clean without deleting evidence.
