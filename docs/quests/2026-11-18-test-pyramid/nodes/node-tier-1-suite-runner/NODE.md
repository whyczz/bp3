---
date: 2026-11-18
quest: ../../QUEST.md
node: tier.1
status: proposed
---

# tier.1 - suite-runner: today's suites, in parallel, isolated

## TL;DR

`scripts/run-suites` reads `test/suites.tsv` and runs every suite
in parallel. Each suite starts from an empty environment plus a
named allowlist, with its own HOME and TMPDIR and a fixed budget.
Suites flagged `serial` never overlap each other. `harness.sh`
splits along its 17 `# ---` sections; the setup they share moves to
`test/harness/lib.sh`. No assertion is rewritten, so this is the
first wall-time win: from 170s toward the longest single suite
(pi-tree, 23s, once `harness.sh` is split).

## Acceptance gates

Design trace (nothing has run):

```text
$ scripts/run-suites --tier fixture,slow
workers 4  suites 24  HOME isolated
  ok   g            15.9s  (budget 30)
  ok   harness      44.0s  (budget 60)
  ok   pi-tree      22.8s  (budget 40)
  ...
ok 24/24  wall 47.3s  (serial sum 167.1s)

$ scripts/run-suites --only planted-sleep      # budget 2
FAIL planted-sleep  budget 2s exceeded (killed at 2.0s)
```

```yaml
objective: run the current make check suites in parallel with isolated HOME and enforced budgets
prove by:
  - test -x scripts/run-suites                 # fails today: no runner
  - five consecutive `scripts/run-suites` runs over every suite in test/suites.tsv
  - planted suite that writes "$HOME/.bp3-leak" and exits 0
  - planted suite `sleep 999` with budget_s 2
  - planted pair of serial suites that each hold a lock file for 1s
  - caller exports GIT_DIR=/nonexistent and BP3_DECIDER=x; a planted suite prints its env
  - each harness piece run alone in a fresh runner, and all pieces in random order
done when:
  - all five runs exit 0, and wall time for each is <= longest suite + 10s
  - the real "$HOME/.bp3-leak" does not exist after the planted run
  - the planted sleep fails by name within 3s, and its process group is gone
  - the two serial suites never hold the lock at the same time
  - the planted env suite sees neither GIT_DIR nor BP3_DECIDER, and sees HOME, TMPDIR, BP3_SUITE, GIT_CONFIG_NOSYSTEM=1
  - every harness piece passes alone and in any order; the harness diff moves assertions without changing them
  - run-suites --report prints actual vs budget for every row
```

## Diagram

```text
test/suites.tsv ─► run-suites ─┬─► worker 1: HOME=/tmp/s1 TMPDIR=/tmp/s1/t  suite a
 name tier cmd                 ├─► worker 2: HOME=/tmp/s2 ...               suite b
 budget_s serial               ├─► worker N
                               └─► serial lane (one at a time)
           each suite: own process group; budget overrun -> kill group, FAIL
           output: one line per suite, then "ok N/N wall Xs" or the failures
```

## Pseudocode

```python
rows = read_tsv("test/suites.tsv")               # name tier cmd budget_s serial why paths
todo = [r for r in rows if r.tier in tiers]
pool, serial_lane = Pool(workers=ncpu()), Lane()
for r in todo:
    home = mkdtemp(f"bp3-suite-{r.name}")
    env = {**allowlisted(os.environ),            # env -i + PATH, LANG, SDKROOT, opam, node
           "HOME": home, "TMPDIR": f"{home}/t", "BP3_SUITE": r.name,
           "GIT_CONFIG_NOSYSTEM": "1"}
    (serial_lane if r.serial else pool).submit(run_budgeted, r.cmd, env, r.budget_s)
results = wait_all()
for res in results:
    if res.timed_out: kill_process_group(res.pgid)
print_lines(results); exit(0 if all(r.ok for r in results) else 1)
```

| Field | Value |
|---|---|
| Intent | cut make check wall time by running suites at once, safely |
| Lane | standard |
| Output | `scripts/run-suites`, `test/suites.tsv`, `test/harness/lib.sh` plus the split harness pieces, the five-run timing log. The runner is OCaml (`src/quest/run_suites.ml`, pure core `src/quest/suites.ml` unit-tested in `test/unit/test_suites.ml`), linking `unix` and the engine library (`bp3_quest`, with yojson and str) and no new dependency; `scripts/run-suites` execs it (owner, 2026-11-19: no perl, fewer deps) |
| Acceptance | goal block above; fails today (`scripts/run-suites` does not exist) |
| Depends on | none |
| Tests | known cases: planted suites under `test/run-suites/` (HOME leak, env leak, budget overrun, serial lock) and the black-box self-test `test/run-suites.sh` (signals, closed reader, stragglers, launch order); unit cases and property-based laws over the pure core in `test/unit/test_suites.ml` (launch order is a stable permutation, a printed row parses back, a budget never un-fires) |

| Suite-table column | Meaning |
|---|---|
| name | short id used in output and by `check-changed.sh` |
| tier | `fixture` or `slow`; slow iff the suite proves what no fake can: a real process tree, signals, real wall-clock waits, or concurrent writers (the unit tier runs through dune and node, not here) |
| cmd | the command line, run from the repo root |
| budget_s | hang guard (red-ink R2'): hand-set integer seconds, max(60, 6x the suite's time under the runner on a quiet machine), rounded up to 30s; `run-suites --report` prints actual vs budget, and slowness is never failed |
| serial | `1` if the suite touches the real repo tree |
| why | one line, required on slow rows: what the suite proves that no fake can |
| paths | globs that select the suite for a changed file; `check-changed.sh` reads them |

## Prose

The 2026-11-18 profile shows 170.40s of serial time, with five
suites making up 120s. Running them at once is the boring fix the
quest's red chair named first, so it lands before any test is
rewritten. The runner began in bash with perl one-liners for
process groups, a millisecond clock and signal resets; six grading
rounds went to bash job-control edge cases. On the owner's call
(2026-11-19) it is OCaml like the engine: fork, setsid and signal
handlers that only set a flag, so a suite forked just before a
signal is still reaped, and no helper language is needed.

HOME isolation also fixes a red-chair finding: suites share the
real `~/.bp3` and git config today. The budget turns a hung suite
into a named failure instead of a stalled check.

Edge cases: a suite that spawns daemons (pi-tree) must die with its
process group; the runner kills the group, not just the leader. A
suite that needs the built binary runs after `dune build`, which
`make check-full` does once before calling the runner. Today's
`skills.sh` renders into the real repo, so it is `serial` until
tier.2 points it at a temp copy.

The `harness.sh` split (red-ink R1) is not purely mechanical:
section 6 builds the `done-q`, `gate-q` and `toy` quests plus
`$store` and `$LIVE`, and sections 7-14 read them.
`test/harness/lib.sh` holds the prelude (temp repo, `q()`, `h()`,
`fail()`) and a `fixture_children` function; each piece calls the
fixtures it needs, so setup reruns per piece, in parallel. The env
allowlist (R5) exists because a check started from a git hook
inherits `GIT_DIR`, which would point every temp-repo `git` call at
the real repo.
