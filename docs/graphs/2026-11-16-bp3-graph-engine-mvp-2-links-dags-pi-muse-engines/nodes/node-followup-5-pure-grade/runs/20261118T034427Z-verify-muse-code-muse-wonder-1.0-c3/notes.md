# followup.5 pure-grade — verify run notes, cycle 3

Run: 20261118T034427Z-verify-muse-code-muse-wonder-1.0-c3
Bound commit: 84be74a6ee6a97288269e37732a952820d982853
Harness: muse-code / muse-wonder-1.0 (link claim returned expected run_id)
Stance: pure grade — return verdict as data, zero `bp3 g u` calls by this child.

## Claims checked (fresh, this session, at bound commit)

- pure audit / single cast / safe replay / pushback superseded, empty fix, blocked / audit reuse (3 rows) / mechanical never-blocks, disagreement-at-cap, live-cycle-zero-owner — `node test/bp3g-grade.test.mjs` — `bp3g-grade tests: ok` exit 0
- fix ledger live — `node test/bp3g-node.test.mjs` — `bp3g-node tests: ok` exit 0
- mechanical live cycle — `./test/bp3g.sh` — node-loop/bp3g-node/bp3g-grade/bp3g-land/bp3g-conduct all ok exit 0
- regression — `make check` — `MAKE_CHECK_EXIT:0` (start 2026-11-18T03:44:53Z, end 04:01:07Z; all steps ok incl. dogfood-parallel, bp3g, completion, release, install)
- completion flags — `./test/completion.sh` — `completion tests: ok`; `--verify-verdict`/`--mechanical` present in completions/_bp3:6, completions/bp3.bash:6 and src/graph/main.ml parse_flags
- adherence — HEAD `84be74a6ee6a97288269e37732a952820d982853` matches bound commit; graph read shows state handed_off cycle 3 commit 84be74a; handoff run folder 20261118T031254Z-handoff-...-c3 present with notes/tape

## Lessons

- The supplied matrix regression row was `missing` only because its 240s timeout killed `make check` (`Terminated: 15`). Fresh full run needs ~16 min (bp3-pi extension suite alone ~290s); a timeout-missing row must be re-run with adequate budget, not treated as a failure.
- Verify must judge on fresh output, not the matrix quote: re-running resolved the sole missing row to pass, so no gated row remains fail/missing.
- Untracked run folders for the sibling node/grade runs appear in porcelain during grading; they are run evidence, not hand-edited state at the bound commit.
