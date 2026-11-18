# Author notes — node-followup-5-pure-grade cycle 4 (run 20261118T040308Z-handoff-muse-code-muse-wonder-1.0-c4)

Bound fix: grade of 84be74a — `timeout 240 make check` died at
./test/g.sh (exit 124, no green). Diagnosis: not a deadlock;
two compounding slowness bugs made the gate wall-clock bound.

## Diagnosis (measured, this environment)

1. test/g.sh is ~250 `bp3 g` calls over a fixture that grows
   to ~45 nodes. At 84be74a every call re-read every ledger
   with fresh git subprocesses (one graph read at 15 nodes =
   106 git calls, 1.57s; cost grows ~60ms per added node), so
   the suite alone exceeded 290s unfinished (46s user + 48s
   sys in the first 120s, progress ~line 290 of 624 at 100s).
   The cycle-3 green claim did not reproduce here.
2. Behind g.sh, extensions/bp3-pi/test hung indefinitely:
   `harness watch` on a minted-but-unclaimed run has no
   InitRecord (run_config_records keeps claimed only), so it
   scanned both harnesses' tape roots and read a 4.5GB /
   2,985-file muse session corpus per call (watch >30s CPU,
   killed). listRuns calls watch per run config.

## Fix (root cause, no suite weakened)

- src/graph/gitx.ml: per-process tip/show caches plus one
  `git cat-file --batch` reader for ledger reads; caches
  invalidated on every ref move (commit_files, land).
  src/graph/store.ml: epoch-keyed list_refs cache; allocation-
  free contains_sub (was String.sub per offset, quadratic on
  tape texts). src/graph/main.ml: invalidate after land's
  direct update-ref. Graph read at 15 nodes: 106 -> ~40 git
  calls, 1.57s -> 0.56s.
- src/graph/harness.ml: scan_harnesses/config_harness — a
  minted run's config names its harness, so find-tape/watch
  scans read that harness's tape roots only. Watch on the
  minted crash run: >30s -> 0.25s, same verdicts.

## Per-suite timings after the fix (this host)

g.sh 125s (was >290s unfinished), harness 109s (fixture
sleeps 30/60 by design), dogfood-parallel 37s, ready 27s,
pi-tree 24s, bp3-pi 21s / 13 pass (was unbounded hang),
blocked 7s, worktree 8s, context 7s, dogfood-link 6s,
diagram 5s, link 4s, hooks 4s, completion 4s, tape 3s,
config 2s, install 2s, release 1s, cleanliness <1s;
lint, skills (134 assertions), build, bp3g ok.
Full `make check` run to exit 0 at the fix commit (see tape).

## Lessons

- A one-shot CLI pays full-repo scans per call; cache within
  the process and invalidate on write, or suites scale as
  calls x nodes x subprocesses.
- Record-less fallbacks that scan $HOME corpora are
  environment-sized time bombs; narrow by the run's own
  config first. Verbatim tape text was never parsed into
  facts; all timings above are from `time` on real suites.
