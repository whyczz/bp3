# Verify c2 — exp-followup-2-workflow-birth @ e37190a

Fresh evidence (this session, tee'd to tape.log):
- `git status --porcelain` (excl. harness `.bp3-context.json`): empty, exit 0. The one untracked file is harness-written (`BP3_G_BIN` context stamp from the parallel grade child), not hand-edited state.
- `git show e37190a`: clean commit, 1 file (conduct-cycle2.md, +59).
- `./bin/bp3 skills check`: `{"ok":true,"fresh":["node-loop","bp3g-grade","bp3g-land","bp3g-node"]}`.
- `node test/bp3g-grade.test.mjs test/bp3g-land.test.mjs test/bp3g-node.test.mjs test/node-loop.test.mjs test/bp3g-conduct.test.mjs`: `bp3g-grade tests: ok`, exit 0.
- `bash test/skills.sh`: `skills tests: ok (134 assertions)` — backdated-render fixtures (E_RENDER_STALE) pass.
- `bash test/harness.sh`: `harness.sh: all checks passed`.
- conduct-cycle2.md (committed at bound commit) records the real foreign-dialect conduct: fixture `2026-11-17-followup2-fixture` node->grade->land to landed, 0/7 read refusals; matrix quote commit fafcc14 matches.

Lessons: harness `.bp3-context.json` churns between parallel children — judge hand-edited state excluding harness artifacts, never by raw porcelain alone.

## Verdict cast outcome
All evidence checks PASS (above). The verify state-edge cast was refused:
`E_ILLEGAL_EDGE {state:"approved", edge:"verify", legal_edges:["land","block","delete"]}`.
Cause: parallel dispatch race — the grade child cast grade (handed_off -> approved)
while this verify child was still running its fresh test suite; verify is only
legal from handed_off. First cast attempt also resolved to the grade claim
(session rung beats BP3_RUN_ID env hint; all parallel children share one host
session_id) with W_CONTEXT_ENV_MISMATCH. No state was hand-edited to force it.
