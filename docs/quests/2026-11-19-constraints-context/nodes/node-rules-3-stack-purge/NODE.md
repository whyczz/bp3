---
date: 2026-11-20
quest: ../../QUEST.md
node: rules.3
status: proposed
---

# rules.3 - stack-purge (follow-up): remove the perl and python the census missed

## TL;DR

The signed stack has no perl or python, but the repo still runs both:
perl one-liners in 13 test files and in a finished migration script,
and a python3 pty driver behind the Ctrl-C probes in
`test/run-suites.sh`. This node removes them by the owner's three
calls (2026-11-20). The perl lines become sed. The migration script
is deleted. The Ctrl-C probes send SIGINT and SIGQUIT to the runner's
process group instead of typing into a pty. rules.2's lint then
lands on a clean repo.

## Acceptance gates

Observed today:

```text
$ git ls-files | grep -v '^docs/' | grep -v '\.md$' | xargs grep -l -E '(^|[;&|(]|=[^ ]* )[[:space:]]*(perl|python3?)[[:space:]]'
scripts/migrate-quest-rename.sh
test/blocked.sh
... (13 test files)
test/run-suites.sh
```

Design trace:

```text
$ git ls-files | grep -v '^docs/' | grep -v '\.md$' | xargs grep -n -w -E 'perl|python3?'
(no output)
$ ./test/run-suites.sh
run-suites tests: ok (<n> assertions)        # Ctrl-C x1, x3 and Ctrl-\ probes now by process-group signal
$ make check-full
run-suites: ok 26/26
```

```yaml
objective: no tracked code outside docs runs perl or python, and every probe still proves what it proved
prove by:
  - the grep above returns nothing
  - test/run-suites.sh passes, and its group-signal probe fails against a
    planted runner that exits 130 on INT without reaping its suite
  - test/check-tiers.sh passes with the fossil case on migrate-graph-rename.sh
  - make check-full green
done when:
  - zero perl or python words in tracked code outside docs/ and *.md
  - the three Ctrl-C probes (int:130, int3:130, quit:131) still check exit code,
    suite dead, temp dir gone, and no job notices
  - scripts/migrate-quest-rename.sh is gone, and so is its sweep exemption row
```

## Diagram

```text
13 tests: perl -pi -e 's/^max_cycles…/'  ──► sed 's/^max_cycles…/' f > f.tmp && mv f.tmp f
migrate-quest-rename.sh (done 2026-11-18)  ──► git rm; check-tiers fossil ──► migrate-graph-rename.sh
run-suites.sh 2c: python3 pty.fork, type ^C ──► set -m; runner & (own pgid); kill -INT -- -pgid
                                                 (a terminal sends ^C to its foreground process group)
```

## Pseudocode

```python
for f in thirteen_tests:
    replace(f, "perl -pi -e 's/^max_cycles: .*/max_cycles: 1/' P",
               "sed 's/^max_cycles: .*/max_cycles: 1/' P > P.tmp && mv P.tmp P")
git_rm("scripts/migrate-quest-rename.sh"); drop_exemption_row(sweep); fossil_case.use("migrate-graph-rename.sh")
for keys, code in [("int", 130), ("int3", 130), ("quit", 131)]:
    rpid = start_in_own_process_group(runner, only="hold")   # set -m; & ; set +m
    wait_for(hold_pid_file)
    for sig in keys_to_signals(keys):                         # int3: three INTs, 0.3s apart
        kill(-rpid, sig)
    assert wait(rpid) == code and dead(hold_pid) and empty(runner_tmp) and no_notices(output)
```

## Tables

| Field | Value |
|---|---|
| Intent | the repo matches the stack the owner signed, before the lint enforces it |
| Lane | standard (edits the runner's signal probes, where tier.1 spent six rounds) |
| Output | 13 test files, `test/run-suites.sh`, `test/check-tiers.sh`, `scripts/check-retired-terms.sh`; `scripts/migrate-quest-rename.sh` deleted |
| Acceptance | the grep returns nothing; run-suites probes pass and fail on a planted non-reaping runner; check-full green |
| Depends on | none (rules.2 depends on this) |

| Probe | Before | After |
|---|---|---|
| int:130 | python3 types `\x03` into a pty | `kill -INT -- -$rpid` |
| int3:130 | three `\x03`, 0.3s apart | three `kill -INT`, 0.3s apart |
| quit:131 | `\x1c` | `kill -QUIT -- -$rpid` |
| exit code | python saw a signal death as negative | `wait` gives 128+N either way; the dead-suite and empty-temp-dir checks prove the runner handled it |

## Prose

The 2026-11-19 census said perl and python were gone. Its `git grep
'\bperl'` failed on the `\b`, and a plain grep misses `TMPDIR=x python3
...`, where an env assignment comes before the command. rules.2's lint
has to treat that prefix as command position too.

What a pty bought: a terminal sends Ctrl-C to its foreground process
group. Suites run in their own sessions, so only the runner gets the
signal and must reap them. Starting the runner as its own process
group (`set -m` for that one launch) and signalling the group gives
the same delivery without a pty. What it loses (owner, 2026-11-20:
"Rewrite without a pty"): the tty line discipline itself, and
SIGHUP-on-close behavior. Probe 2d still covers HUP by signal.

Edge cases:

- **INT and QUIT ignored for `&` jobs.** bash ignores both for
  background commands when job control is off. `set -m` turns it on
  for the launch, so the runner starts with default handlers, as
  python's driver forced by hand.
- **Job notices.** The test's own shell may print a notice when the
  job dies. The probe checks the runner's output file only, which is
  what the pty captured.
