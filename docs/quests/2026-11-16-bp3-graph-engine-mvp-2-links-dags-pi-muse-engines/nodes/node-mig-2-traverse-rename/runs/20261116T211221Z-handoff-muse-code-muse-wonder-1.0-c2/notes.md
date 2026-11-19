# mig.2 traverse-rename — run notes (c2)

- Cycle 1 rename (65d55af) was clean but graded `missing` on
  `traverse conducts`: only per-workflow mock parity existed, no
  end-to-end conduction artifact. Cycle 2 adds exactly that row.
- New `test/traverse-conduct.test.mjs`: a conductor loop over the
  traverse dispatch table drives one fixture node through the real
  `node-loop.js` -> `induct-grade.js` -> `quest-land.js` files
  against a shared fixture state machine (todo -> handed_off ->
  approved -> landed/exp_fin), asserting dispatch order, stage
  order (author,audit,grade,verify,land), and bound-commit flow.
  Wired into `test/traverse.sh`; mock host only, no agent calls.
- Mock-host lesson: dispatch stage children by label, not input
  text — grade/verify briefs mention `harness find-tape` in ladder
  text, so input-matching intercepts them and starves the matrix.
- Verified: `./test/traverse.sh` (incl. traverse-conduct: ok),
  `./test/skills.sh` (121 assertions), `bp3 skills install
  --harness=all` leaves tree clean, full `make check` exit 0.
