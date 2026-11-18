# Grade notes — exp-dogfood-2-parallel-drive c1

Verdict: needs_fix (code-reviewer fix_first).

## Claims checked (rungs 1-4, no whole-tape read)
- Rung 1: EXPERIMENT.md acceptance = 8 cases incl. Pi tree death+revival, Muse parity bubble; no deferral to a named successor exp in the record.
- Rung 2: commit 5140695 diff = Makefile wiring, src/quest/harness.ml O_EXCL mint fix, new test/dogfood-parallel.sh (222 lines). Harness fix is correct: O_EXCL reserve, fsync, unlink-on-error, 1s retry x5 preserving run-id spelling; explicit --run-id still E_EXISTS. Comment agrees with code. No hand-edited state; git status clean.
- Rung 3 (run, not read): `bash test/dogfood-parallel.sh` exit 0, scorecard ready_wall_ms 3977 < serial_sum_ms 6926, wall_saved 2949, tokens null with named cause. Covers true parallelism, isolation, serial land, scorecard, quality floor, env run-id.
- Rung 2/3 gap: `grep -n "Pi|bubble" test/dogfood-parallel.sh` exit 1 (no matches). Pi/Muse bubble cases have no coverage in this drive; mvp.5 test/pi-tree.test.mjs + test/blocked.sh prove the state/tree layer separately, not this exp's seeded parallel-drive case, and no Muse parity bubble test exists. Gated matrix rows verdict=missing therefore block ship per instructions.

## Lesson
Deferred-vs-missing must be named in EXPERIMENT.md itself; a handoff note claiming coverage elsewhere does not gate-pass an acceptance case.

## Grade call outcome
Grade call returned E_ILLEGAL_EDGE: state is now `blocked` (legal resume/delete), not `handed_off`. A parallel verify child blocked the node at 2026-11-17T06:57:35Z for the same missing Pi/Muse rows. No resume attempted (human gate). Verdict intent remains needs_fix; the block already records that negative outcome.
