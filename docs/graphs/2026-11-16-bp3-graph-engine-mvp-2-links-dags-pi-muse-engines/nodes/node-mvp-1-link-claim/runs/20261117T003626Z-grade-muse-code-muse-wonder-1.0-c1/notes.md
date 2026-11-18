# grade notes — exp-mvp-1-link-claim @ 09b9d8d

## Verdict basis (code-reviewer procedure)
- Claims from commit message + EXPERIMENT.md acceptance read first (rung 1).
- Rung 2: harness.ml claim is a real O_EXCL CAS on claims/<run_id>.claim (single write+fsync), losers get E_LINK_SPENT naming first_claim; depth guard `if depth > thresholds.Config.depth_cap` at harness.ml:2219; run config (creator/claim/tape_path) replaces InitRecord, record-init refuses E_RETIRED. Comments agree with code.
- Rung 3 run, not read: `./test/link.sh` -> "link tests: ok"; `node --test extensions/bp3-pi/test/bp3-pi.test.mjs` -> pass 13 incl. "missing bp3-pi extension refuses E_SETUP before any spawn".
- No critical/major findings. Minor note: worktree shows uncommitted .agents/workflows/* mirrors of the committed skills/traverse/workflows/* change; bound commit itself is clean (HEAD == 09b9d8d) and gated rows pass.
- Decided at rungs 1-3; no whole-tape (rung 5b) read needed.

## Lessons
- Judge the bound commit, not worktree mirror dirt.
- The claim marker, not the config edit, is the CAS — verify O_EXCL in code, not just test names.
