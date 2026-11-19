# exp-mvp-1-link-claim — author notes

## What landed

- `bp3 harness link mint|claim|lookup|cleanup` (alias `l`): mint writes
  `runs/<run_id>.json` (state minted, `creator:{run_id,depth,harness,model,minted_at,token_hash}`)
  plus `links/<token_hash> -> run_id` and returns the one-time `bp3link_` token.
  Claim is a CAS on an O_EXCL `claims/<run_id>.claim` marker (single write + fsync):
  exactly one winner completes the run config (`state claimed`, `claim:{session_id?,pid,cwd,claimed_at}`
  via temp+fsync+rename), writes `by-session/<session-id>` and the desk context;
  every later claim refuses `E_LINK_SPENT` naming `first_claim{session_id,pid,ts}`.
  Lookup resolves session-id (or run-id) to run-id/graph/node/edge in one call.
  Cleanup removes only still-`minted` configs of one graph; claimed rows byte-identical.
- Session discovery: `--session-id`, else `BP3_SESSION_ID`, `MUSE_SESSION_ID`/`MUSE_THREAD_ID`,
  `PI_SESSION_ID`/`PI_SESSION_FILE` (session file identity); none offered still claims on pid+cwd.
- Depth: mint refuses `E_DEPTH` when depth exceeds `thresholds.depth_cap` (default 3, config-overridable).
- Run config replaces InitRecord: `record-init` (and alias `r`) refuses `E_RETIRED`;
  `bind-tape` writes `tape_path` into the run config when claimed (legacy derivation binding kept
  for pre-link Runs, still pinned `E_EXISTS`); supervisor/find-tape/watch fold claimed run configs
  through the same `derive_lifecycle` words (minted=init, finished from tape+dead pid observed).
- Pi: dispatcher mints before spawn, spawns the child explicitly with `--extension <bp3-pi>`,
  carries `BP3_LINK_TOKEN` (no typed `BP3_RUN_ID`); missing extension refuses `E_SETUP` pre-spawn;
  unclaimed children are fallback-claimed with the tape's session identity. `list_runs` relays watch.
- Traverse workflows (node-loop/induct-grade/quest-land) mint links; children claim first and stamp
  `BP3_RUN_ID=<claimed run_id>` on their edge call. Induct-grade prompts now build after both mints.

## Lessons

- Prompt construction order is a real bug class: induct-grade built grade/verify briefs before
  minting their links, so claim notes were empty; mints must precede brief assembly.
- The claim marker, not the run-config edit, is the CAS: losers read the winner's facts from the
  marker, so `E_LINK_SPENT` can name the first claimant without trusting a torn config.
- Depth boundary chosen literally: refuse `depth > depth_cap` (depth == cap allowed); normal
  root/node/edge mints sit at depths 1–2, so the cap only stops fan-out beyond the tree.
