# Run notes — exp-mvp-2-context-resolution (author, cycle 1)

Claimed `bp3link_7daa…` as run
`20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1`
(session rung: this session's MUSE_SESSION_ID).

## What landed

Context resolution in the CLI doors (mvp.2):

- `Config.resolve_context` in
  [config.ml](../../../../../../../../src/quest/config.ml):
  session rung first (latest claimed run for the observed
  session-id), desk rung second (claimed runs whose stored
  desk names cwd, corroborated by the claim's
  `.bp3-context.json`, checked against cwd). Reads only;
  never creates the store. Resolution refuses to guess:
  more than one live claimed run at a desk with no session
  rung is `Ambiguous`, surfaced as `E_NO_CONTEXT` naming
  the live run_ids.
- Session-id discovery moved to one spelling,
  `Config.observed_session_id`; link claim reuses it.
- `bp3 e` door ([main.ml](../../../../../../../../src/quest/main.ml),
  routed in [bin/bp3](../../../../../../../../bin/bp3)):
  bare `bp3 e` prints resolved context + source rung +
  state + legal edges + thresholds; `bp3 e <edge>` takes
  the claimed run's edge with no graph/node/run-id typed.
  No rung, or an ambiguous desk, refuses `E_NO_CONTEXT`.
- Stamping: the claimed run-id wins over the `BP3_RUN_ID`
  env hint in verdicts (`Store.stamp_run_id`) and ledger
  lines (`identity`); a disagreeing env warns
  `W_CONTEXT_ENV_MISMATCH`. Unclaimed explicit edge calls
  keep legacy behavior plus one `W_CONTEXT_UNCLAIMED`
  (renders merge warnings once, in
  [render.ml](../../../../../../../../src/quest/render.ml)).
  Quest/exp creates and reads keep the exact legacy shape
  (config.sh's no-new-warnings contract).
- `e` added to reserved slugs, q/e help, and bash+zsh
  completions; `test/context.sh` committed and wired into
  `make check` + shellcheck.

## Lessons

- The same session-id can claim more than once in this
  harness (a node claim and an edge claim shared one
  MUSE_SESSION_ID here). The session rung must take the
  latest claim, matching the by-session index the last
  claim wrote; first-match resolved this run to the wrong
  node run until fixed.
- Stored desks arrive in mixed spellings (absolute at
  mint, relative from the conductor). Desk matching has
  to canonicalize as-stored, root-relative, and
  common-dir-relative spellings before comparing to cwd.
- A claimed desk writes `.bp3-context.json` into the
  repo, which trips handoff's dirty-tree check; tests
  (and children) must remove it before handing off.

## Verification

- `./test/context.sh`: ok (claimed session full
  handoff→grade→verify→land drive with zero context
  flags, desk-rung fresh shell, mismatch, ambiguity,
  no-false-claim, unclaimed warning cases).
- `make check`: full gate (lint, skills, dune build,
  q/harness/config/link/context/worktree/tape/hooks/
  traverse/completion/release/install, pi tests) — see
  tape.log for the final exit line.
- Live probe: `env -u BP3_RUN_ID ./bin/bp3 e` in this
  desk resolved this run by session, state `todo`,
  legal edges `[handoff, block, delete]`.

Final: commit 63d49cd86c64452f10d64e0fa7c2c6f231e3db37, handoff handed_off, make check exit 0.
