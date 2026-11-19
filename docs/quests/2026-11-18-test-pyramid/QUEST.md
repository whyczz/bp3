---
status: proposed
home_repo: bp3
date: 2026-11-18
---

# test-pyramid: unit-first make check

TL;DR
`make check` becomes the inner loop: lint, OCaml unit tests
(OUnit2 table cases plus QCheck properties), and the JS mock-host
tests, in seconds. `make check-full` becomes the grade/land gate:
the same plus the fixture and slow suites, run in parallel by one
runner with an isolated HOME and a time budget per suite. Old suites
are retired only through a coverage map and a mutation table, never
silently. The one decision made: unit-only `make check` (owner,
2026-11-18), with `make check-full` holding the grade/land gate.

ELI5
Today every test drives the whole program from the outside: about
520 launches of bp3, each one spawning git, run one after another.
That takes about three minutes. This quest tests the small pieces
directly (milliseconds each), runs the remaining outside-in tests at
the same time instead of in a line, fixes the three places where the
engine itself sleeps, and deletes an old test only after showing
that the new ones catch everything it caught.

## Context

Predecessor: [2026-11-14-bp3-unit-tests](../2026-11-14-bp3-unit-tests/QUEST.md),
abandoned by the owner on 2026-11-15 ("lets abandon this quest";
its rollup state is `deleted`). Its red-ink rounds settled a vocabulary
(hermetic, test-name kinds, generator layers, Tape replay). That quest
is research input here, not adopted design: each carried idea below is
re-decided and marked. The new pressure is wall time. The 11-14 quest
accepted a 24.6s `make check`; today it is 170.40s.

## Terms

| Term | One line |
|---|---|
| unit tier | `dune test` plus the JS mock-host tests: no bp3 launch, no git, milliseconds per test |
| fixture tier | shell or JS fixtures that launch the real binary: one fixture per CLI verb or door, run in parallel. Suite-table tier value `fixture` (red-ink R6: adopts the repo's existing word; was "contract tier") |
| slow tier | a suite is slow iff it proves what no fake can: a real process tree, signals, real wall-clock waits, or concurrent writers (red-ink R7). Its table row carries a one-line `why`. Today: pi-tree, dogfood-link, dogfood-parallel, and the harness watch, supervisor, derivation-concurrency and claim-race sections |
| `make check` | inner-loop gate: lint, unit tier; target under 15s |
| `make check-full` | grade/land gate: `make check` plus the fixture and slow tiers through `run-suites`; target 60s or less |
| `run-suites` | `scripts/run-suites`: the parallel runner; reads the suite table, gives each suite its own HOME and TMPDIR, enforces its budget |
| suite table | `test/suites.tsv`: one row per suite (name, tier, cmd, budget_s, serial, why, paths); `paths` holds the globs that select the suite for a changed file (red-ink R3, reopened). The single source for `run-suites`, `check-changed.sh`, and lint |
| budget | a suite's hang guard: a hand-set integer `budget_s`, max(60, 6x its time under the runner on a quiet machine), rounded up to 30s; an overrun fails the suite by name. It catches hangs, not slowness: slowness is read from `run-suites --report`, never failed (red-ink R2, amended R2' by the owner 2026-11-19 after a busy laptop ran suites 2.5-5x slower and failed 29 of 31 on 2x budgets) |
| serial | suite-table flag for a suite that touches the real repo tree; the runner never runs two serial suites at once |
| suite env | what a suite inherits (red-ink R5): `env -i` plus a named allowlist (`PATH`, `LANG`/`LC_*`, `SDKROOT`, opam vars `OPAM_SWITCH_PREFIX` `CAML_LD_LIBRARY_PATH` `OCAMLPATH`, node vars), then `HOME`, `TMPDIR`, `BP3_SUITE`, `GIT_CONFIG_NOSYSTEM=1`; no `GIT_*` or `BP3_*` leaks; a missing var fails loudly |
| hermetic_fn | a function a unit test calls with every input passed in: no git, process, wall clock, env, or filesystem (carried from 11-14; re-decided: adopted) |
| `Clock` | `src/quest/clock.ml`, the only module that reads the wall clock. Hybrid (red-ink R4): time decisions are pure predicates taking `~now` (`stale`, `silent`, `past_deadline`), tested with literal times; effectful code reads a swappable source (default `Unix.gettimeofday`) that tests pin with `Clock.with_fixed`: `Clock.time ()` gives whole seconds exactly as `Unix.time` did, so every pre-seam site reads it and behavior is unchanged; `Clock.now ()` gives sub-second time for new readers (seam.1's run-id mint). The binary honors no time env var |
| law | a QCheck property that must hold for all generated inputs; test names start `law_` |
| case | a named example or boundary; a table of cases is the "parameter test"; test names start `case_` |
| char | a characterization: pins today's behavior without blessing it; test names start `char_` (kinds carried from 11-14; re-decided: adopted) |
| sample | a real ledger copied from a `bp3/quest/*` storage ref, sanitized (no home paths or session ids), frozen under `test/unit/samples/`, and replayed through the fold by a `case_` test (red-ink R8). Renamed from the 11-14 "Tape" because a run's `tape.log` is verbatim evidence, never parsed; a sample is deliberately adopted test input |
| fake bp3 | `test/fake-bp3/`: a stand-in executable for JS tests that replays transcripts instead of running the engine |
| transcript | a recorded `(argv, stdin, stdout, exit)` row captured from the real binary; `check-full` re-records and diffs them |
| coverage map | `test/COVERAGE.md`: one row per old-suite assertion cluster, naming its new home or the reason it is kept |
| mutation table | planted engine bugs, with the old and new tiers each marked caught or missed; a suite is deleted only if no row reads old caught, new missed |

## Inputs

| Input | Source |
|---|---|
| owner prompt | 2026-11-18: "improve our make check, can we use ocaml unit tests, parameter tests" |
| owner answers | 2026-11-18: unit-only `make check`; retire by coverage map; all four engine fixes; node:test plus fake bp3 |
| timing profile | per-step `make check` on master `cdb4557`+fix, 2026-11-18: 170.40s total (table under Scorecard) |
| red-chair findings | 2026-11-18 test red chair: no unit layer; whole-second clock, no seam; run-id collision sleeps 1s; vacuous assertions; timing flakes; `listRuns` blocks 5s per run; serial unbudgeted runner, HOME shared; mixed JS assertion styles |
| installed libraries | ounit2 2.2.7, qcheck-core 0.91, qcheck-ounit 0.91, OCaml 5.3.0, dune 3.24.0 (`opam list`, this session) |
| pattern reference | `bp3/exp2-astra-author:tests/dune`: library plus one `(test ...)` stanza per file |
| predecessor | `docs/quests/2026-11-14-bp3-unit-tests/` (deleted quest; settled vocabulary only) |

## Outputs

| Output | Shape |
|---|---|
| library split | `src/quest/dune`: `(library bp3_quest (wrapped false))` plus `(executable main)`; no file moves |
| unit suites | `test/unit/dune` plus `test_*.ml`; run by `dune test` |
| `Clock` seam | `src/quest/clock.ml`; `Unix.time` appears nowhere else in `src/quest/` |
| runner | `scripts/run-suites`, `test/suites.tsv` |
| gates | `make check` (unit), `make check-full` (all tiers); `check-fast` folds into `check` |
| engine fixes | sub-second run-id mint with no sleep; `bp3 harness watch --once`; `listRuns` on it |
| JS harness | `test/fake-bp3/` plus transcripts; every JS test on `node:test` and `node:assert/strict` |
| retire records | `test/COVERAGE.md`, `test/MUTATIONS.md`; old suites deleted per row |
| skill text | grade/land skills name `make check-full` (own node, tier.3) |

## Acceptance gates (design trace)

Nothing below has run yet.

```text
$ time make check
lint ok
dune test: test_store 41 ok, test_hooks 18 ok, test_render 9 ok ... (law_ cases 200 each)
node unit: node-loop, induct-node, induct-grade, induct-land, induct-conduct, bp3-pi: ok
real 0m11s

$ time make check-full
run-suites: 14 suites, 4 workers, HOME isolated
  fixture   q-door 3.1s  link 2.0s  desk 1.8s ...  ok
  slow      pi-tree 9.0s (budget 20)  dogfood-parallel 8.2s (budget 20) ...  ok
transcripts: re-recorded 37, drift 0
real 0m52s

plant: Store.fold_state_name stops mapping "submitted"
$ dune test
FAIL case_fold_reads_a_legacy_submitted_line_as_handed_off
```

| Check | Done when |
|---|---|
| inner loop | `make check` exits 0 in under 15s wall on this machine, five runs in a row |
| gate | `make check-full` exits 0 in 60s or less, five runs in a row, no flake |
| unit floor | every hermetic_fn named in unit.3 and unit.4 has at least one `case_` or `law_` test |
| non-vacuous | each unit node's planted mutation turns at least one named test red |
| no sleeps | no engine path sleeps on a collision; `listRuns` over 3 live runs returns in under 1s |
| nothing lost | every deleted suite has a coverage-map row per assertion cluster, and the mutation table has no row reading old caught, new missed |

## Goal and why

`make check` gates every grade and land, and at 170s each review
cycle pays three minutes before a verdict. Almost all of that time is
process spawns: the engine has no unit layer, so even a ledger fold is
tested by launching the binary against a temp git repo. Process
suites also flake (pi-tree claim races) and some assert nothing (the
harness race passed with a dead pid). A unit tier makes failures
precise and fast; parallelism and three engine fixes cut the rest.

## Success picture

`make check` takes seconds and is what a session runs after every
edit. `make check-full` takes a minute or less and is what graders
and the lander run. A red unit test reads as a sentence that names
the broken invariant. No old suite was deleted without a map row and
a mutation row. `trial` at landing records both timings side by side
with the 170.40s baseline.

## Scope

| In | Out |
|---|---|
| library split and `dune test` (OUnit2, QCheck) | new frameworks (no Alcotest, no ppx_expect) |
| `Clock` seam for all 20 `Unix.time` sites | rewriting harness process logic beyond the seam |
| run-id mint, `watch --once`, `listRuns` | other engine features |
| `run-suites`, suite table, HOME and TMPDIR isolation, budgets | CI service setup (none exists) |
| JS: node:test plus assert/strict everywhere, fake bp3 with transcripts | testing pi or Muse themselves |
| retire old suites by coverage map and mutation table | coverage tooling (bisect_ppx) |
| skill text naming the gates (tier.3) | the 11-14 test-split framing standard for future quests (stays with the deleted quest; re-icebox if wanted) |

## Human touchpoints

| When | What the owner does |
|---|---|
| now | `/red-ink` this file; settle the open questions |
| approval | quest governs build; `bp3 q c` creates it |
| tier.3 | reads the skill diff (skills are how children behave) |
| retire.1 | reads the coverage map and mutation table before the deletion commit lands |
| landing | `trial`: before and after timings, one planted bug caught live |

## Nodes

### Milestone: tier

### tier.1 - suite-runner
`scripts/run-suites` plus `test/suites.tsv`: today's suites, run in
parallel, HOME and TMPDIR isolated, a budget per suite. `harness.sh`
splits along its 17 `# ---` sections into separate suite rows, with no
assertion changed, so the runner can run its pieces side by side
(red-ink R1). The sections share setup (section 6 creates the
`done-q`/`gate-q`/`toy` quests, `$store` and `$LIVE` that sections
7-14 read), so the split first extracts `test/harness/lib.sh`: the
prelude (temp repo, `q()`, `h()`, `fail()`) plus a `fixture_children`
function; every piece sources it and calls only the fixtures it needs
(red-ink R1, reopened at the closing red chair). Each suite runs under
the allowlisted suite env (R5). The biggest wall-time win with no test rewritten.
Depends on: none.
[record](nodes/node-tier-1-suite-runner/NODE.md)

### tier.2 - gate-split
`make check` becomes lint plus the unit tier; `make check-full` adds
`run-suites`; `check-fast` folds in; `check-changed.sh` reads the
suite table. Depends on: tier.1, unit.1, js.1.
[record](nodes/node-tier-2-gate-split/NODE.md)

### tier.3 - gate-skills
Skill-change node: induct, induct-inline, induct-yolo, using-bp3, and
the grade/land workflows name `make check-full` as the gate.
Depends on: tier.2. [record](nodes/node-tier-3-gate-skills/NODE.md)

### Milestone: unit

### unit.1 - lib-split
`src/quest` builds as a library plus `main.exe`; `test/unit/` gets
its first `dune test` stanza. Depends on: none.
[record](nodes/node-unit-1-lib-split/NODE.md)

### unit.2 - clock-seam
`Clock` owns the wall clock; all 20 `Unix.time` sites go through it.
Hybrid shape (R4): decisions become pure `~now` predicates; loops read
`Clock.time ()` (whole seconds, as before); no `BP3_NOW` knob.
Depends on: unit.1.
[record](nodes/node-unit-2-clock-seam/NODE.md)

### unit.3 - store-laws
Unit tests for the store and scheduler: ledger fold, ledger line
round-trip, legal edges, version order, waves, icebox parsing, Layout
paths. Plus samples (R8): one real node ledger per era (exp-era with
`submitted` edges, e.g. `2026-11-07-bp3-mvp-engine-core` exp-3-fsm;
graph-era; quest-era), sanitized, frozen, fold pinned.
Depends on: unit.1.
[record](nodes/node-unit-3-store-laws/NODE.md)

### unit.4 - edge-units
Unit tests for hooks, render, and CLI flag parsing: run-id parsing,
refusal codes, binding JSON round-trip, stale gate, diagram output.
Depends on: unit.2. [record](nodes/node-unit-4-edge-units/NODE.md)

### Milestone: seam

### seam.1 - run-id-mint
Run-ids carry sub-second time plus a random suffix; a collision
retries at once with no sleep. Shape (red-ink R3):
`20261118T110640.123a7f3Z-<edge>-<harness>-<model>-c<n>`, with
milliseconds and 4 hex inside dash field 1, so ids sort by time and
`parse_edge_cycle` still reads the cycle from the last field.
Depends on: unit.2.
[record](nodes/node-seam-1-run-id-mint/NODE.md)

### seam.2 - listruns-nowait
`bp3 harness watch --once` answers a snapshot and never blocks;
`listRuns` uses it. Depends on: none.
[record](nodes/node-seam-2-listruns-nowait/NODE.md)

### Milestone: js

### js.1 - fake-bp3
JS tests on node:test plus assert/strict; the bp3-pi tests run against
a fake bp3 that replays recorded transcripts. Depends on: seam.2.
[record](nodes/node-js-1-fake-bp3/NODE.md)

### Milestone: retire

### retire.1 - coverage-map
Map every old assertion cluster to its new home, prove it with the
mutation table, then delete the covered suites.
Depends on: tier.2, unit.3, unit.4, js.1.
[record](nodes/node-retire-1-coverage-map/NODE.md)

## Scorecard

| Field | Value |
|---|---|
| Baseline wall | 170.40s `make check`, serial, 2026-11-18 (below) |
| Target wall | `make check` under 15s; `make check-full` 60s or less |
| Context tokens | unmeasured until Runs record it |
| Human-active minutes | red-ink, tier.3 skill diff, retire.1 map read, trial |

Baseline per step (seconds, master, 2026-11-18):

| Step | s | Step | s |
|---|---|---|---|
| harness.sh | 45.85 | context.sh | 5.12 |
| pi-tree.test.mjs | 23.19 | skills.sh | 4.86 |
| bp3-pi.test.mjs | 22.42 | worktree.sh | 4.64 |
| g.sh | 16.17 | dogfood-link.sh | 4.46 |
| dogfood-parallel.sh | 12.22 | lint | 2.97 |
| link.sh | 6.36 | 13 others | 15.94 |
| ready.sh | 5.93 | **total** | **170.40** |

## Risks and red chair

Red chair at framing, 2026-11-18, engineering lens. Every critical or
major concern is settled by a recorded change; none is left as prose.

| # | Sev | Attack | Settlement |
|---|---|---|---|
| 1 | major | Source attack (7.5): the owner's premise "unit tests make check faster" is half true. The time is in process suites (harness 46s, pi-tree 23s, bp3-pi 22s). The boring alternative, running today's suites in parallel, cuts wall time to roughly the longest suite with nothing rewritten. | Node order changed: tier.1 (the runner) is in the first cohort and owes the first win. The unit tier is justified by precision, failure legibility, and enabling retire.1, not by seconds alone. |
| 2 | major | Unit-only `make check` stops proving the binary works end to end, yet CLAUDE.md, AGENTS.md and the induct skills tell graders to run `make check`. A grader would ship a CLI regression on a green inner loop. | Grade and land gate is `make check-full` (tier.2); the skill text moves in its own node (tier.3) with skill-test assertions. |
| 3 | major | Three tier systems would overlap: the new `check`, the new `check-full`, and the existing `check-fast`/`check-changed.sh` selector with its own suite list. | One suite table (`test/suites.tsv`) feeds all of them; `check-fast` folds into `make check`; tier.2 acceptance asserts a single list. |
| 4 | major | The coverage map can lie. The agent that writes the new tests also deletes the old ones, which is the reward-hacking shape the 11-14 references warned about. | retire.1 gates deletion on the mutation table (old caught, new missed blocks), lands new tests and deletions in separate commits so the grader sees new green first, and puts the owner in the loop before the deletion commit. |
| 5 | major | A parallel runner races suites that write the real repo tree (skills renders, `_build`) or share HOME and git config. | Per-suite HOME and TMPDIR; `serial` flag in the suite table for repo-touching suites; tier.1 acceptance requires five consecutive green runs and a planted HOME write that leaves the real HOME untouched. |
| 6 | major | A fake bp3 drifts from the real CLI, so JS tests pass while integration breaks. | Transcripts are recorded from the real binary; `check-full` re-records and diffs them, and any drift fails (js.1 acceptance). |
| 7 | minor | A wrapped library would force `Bp3_quest.` prefixes through `main.ml`. | `(wrapped false)`, both stanzas in `src/quest/dune`; no file moves, so `Layout.engine_src` and release paths are untouched. |
| 8 | minor | `dune test` needs ounit2 and qcheck on every contributor machine. | Recorded in readme setup; `make check` fails with the missing-library message, not a silent skip. |

Strongest attack: #1. It changed the node order and moved the
quest's speed claim onto the runner, where the evidence puts it.

Red-ink opening attack (2026-11-18): the runner cannot beat its
longest suite, and `harness.sh` alone is 45.85s, so `check-full`
would land at 60s or worse until retire.1.3. Settled in R1: tier.1
splits `harness.sh` by section.

Closing red chair (red-ink settle, 2026-11-19), engineering lens:

| # | Sev | Finding | Settlement |
|---|---|---|---|
| 1 | major | R1 assumed `harness.sh` sections are independent; section 6 builds fixtures that sections 7-14 read (variable flow checked) | reopened R1: shared `test/harness/lib.sh` |
| 2 | major | tier.2 demanded one suite list while `check-changed.sh:75-84` keeps a second | reopened R3: `paths` column in `test/suites.tsv` |
| 3 | minor | `Clock.with_fixed` swaps a global ref; an unrestored swap could leak between tests | deliberately open: `with_fixed` restores via `Fun.protect` (unit.2 owner) |
| 4 | minor | "make check under 15s" assumes a warm dune build | deliberately open: tier.2 states warm and cold timings |

Survived: the 60s floor. Per-call times from the 2026-11-18 profile
(139 bp3 calls, 34.1s summed) put the harness watch calls near 13s
total, with the longest supervisor call at 3.2s. After the split,
pi-tree (23s) is the longest suite, so `check-full` lands near 40s.
That is inference from per-call sums, not a measured split run.
Also survived: fake-bp3 drift. Unknown argvs exit 97 and
`check-full` re-records the known ones against the real binary.

## Red-ink decisions

| Round | Slice | Before | After (owner's call) |
|---|---|---|---|
| R1 | Output | 60s `check-full` rests on the runner; `harness.sh` (46s) is one suite until retire.1.3 | "Split harness.sh early": tier.1 splits it along its 17 sections; no assertion changes |
| R2 | Inputs | budget source undecided (fixed vs median multiple) | "Fixed, about 2x measured": hand-set `budget_s`, `--report` for tightening, no history state |
| R3 | Data | run-id `<compact_ts>-...-c<n>`, whole-second, collision sleeps 1s | "ms + 4 hex in field 1": `20261118T110640.123a7f3Z-<edge>-<harness>-<model>-c<n>` |
| R4 | State | 20 inline `Unix.time` reads, no seam; shape undecided | "Hybrid": pure `~now` predicates for decisions, swappable `Clock.now ()` for loops, no `BP3_NOW` |
| R5 | Functions | suites inherit the caller's env (`GIT_DIR`, `BP3_*` can leak) | "Allowlist": `env -i` plus named vars; leaks impossible, gaps fail loudly |
| R6 | Names | middle tier called "contract" (5 repo uses) beside "fixture" (180 uses) | "fixture": tiers are `unit \| fixture \| slow`; node records took the rename at adoption |
| R7 | Concepts | slow tier = a candidate list | "Real-process rule": slow iff it proves a process tree, signals, real waits, or concurrent writers; `why` column per slow row |
| R8 | Concepts | 11-14 "Tapes" undecided; name collides with run `tape.log` | "Now, named samples": unit.3 freezes one real ledger per era under `test/unit/samples/` |
| R1' | Output (reopened) | split assumed independent sections | "Shared lib": `test/harness/lib.sh` (prelude + `fixture_children`), sourced per piece |
| R3' | Data (reopened) | `check-changed.sh` keeps its own path table beside the suite table | "paths column": globs in `test/suites.tsv`; one list |
| R2' | Inputs (amended in build, owner 2026-11-19) | budgets about 2x measured fail a busy machine (29/31 red on load ~10) | "hangs only": budget_s = max(60, 6x quiet time), rounded to 30s; slowness reported by --report, never failed |

## Deliberately open

| Item | Owner |
|---|---|
| `Clock.with_fixed` restores via `Fun.protect`; OUnit runner mode (sequential vs processes) chosen to match | unit.2 author |
| tier.2 reports warm and cold `make check` timings; the 15s target is warm | tier.2 author |
| Icebox consulted, not promoted: `2026-11-17-warden-plug-rules` (row 8 answered by this quest), `2026-11-17-run-profiler-chrome-trace`, `2026-11-18-sqlite-store`, `2026-11-15-bp3-lint`, `2026-11-17-mini-warden-run-budgets` | owner |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | ~~`Clock` shape~~ Settled R4: hybrid (pure `~now` predicates; `Clock.now ()` ref in loops; no env knob). | owner (settled) |
| 2 | ~~Run-id shape~~ Settled R3: `20261118T110640.123a7f3Z-<edge>-<harness>-<model>-c<n>` (ms + 4 hex in field 1). | owner (settled) |
| 3 | ~~Budgets: fixed per suite, or a multiple of a recorded median?~~ Settled R2: fixed, no stored history; amended R2': hang guards, not 2x. | owner (settled) |
| 4 | ~~Which suites are slow tier?~~ Settled R7: the real-process rule (see Terms, slow tier). | owner (settled) |
| 5 | ~~Do Tapes ride in unit.3?~~ Settled R8: yes, renamed **samples**, one per era. | owner (settled) |

## Functional tests (quest level)

These drive the public paths (make targets, the runner, the binary,
files) and prove the nodes compose. Each case is labeled: functional
fixture (same public path, planted or fake input) or end-to-end (real
processes). All are design traces until the quest builds.

| # | Case | Start | Actions | Observable result | Label |
|---|---|---|---|---|---|
| F1 | happy path | clean clone at the landing commit, warm build | `make check`; `make check-full` | both exit 0; under 15s and 60s or less; runner prints `ok N/N` and `drift 0` | end-to-end |
| F2 | refusal, state unchanged | same | plant `fold_state_name` dropping `submitted`; `make check` | exits 1 naming `case_fold_reads_a_legacy_submitted_line_as_handed_off`; `git status` shows only the planted edit | functional fixture |
| F3 | budget overrun | suite table plus a planted `sleep 999` row, budget 2 | `scripts/run-suites --only planted-sleep` | fails by name within 3s; `pgrep -g` finds no survivor; no temp HOME left behind | functional fixture |
| F4 | human gate and recovery | retire.1.1 tables written; one mutation row reads old caught, new missed | try the deletion commit | the grader refuses (`needs_fix`); author adds the missing test; table re-run shows no such row; owner reads both tables; deletion lands | functional fixture |
| F5 | crash and restart | `make check-full` mid-run | SIGINT the runner; run again | no orphan process groups, temp HOMEs removed; the second run is green; the runner keeps no state to rebuild | end-to-end |
| F6 | surfaces agree | landing commit | `check-changed.sh --list src/quest/store.ml`; `record-transcripts --check`; `diff CLAUDE.md AGENTS.md`; `git grep 'make check' -- skills` | the list equals the suite rows whose `paths` match; drift 0; docs identical; every grade/land line says `check-full` | functional fixture |

## Node diagram

```text
cohort 1    cohort 2    cohort 3    cohort 4
--------    --------    --------    --------
tier.1      unit.2      unit.4      tier.3
unit.1      unit.3      seam.1      retire.1
seam.2      js.1        tier.2

edges
unit.1 ─► unit.2 ─► unit.4 ─────────► retire.1
unit.1 ─► unit.3 ───────────────────► retire.1
          unit.2 ─► seam.1
seam.2 ─► js.1 ───► tier.2 ─► tier.3
          js.1 ─────────────────────► retire.1
tier.1 ───────────► tier.2 ─────────► retire.1
unit.1 ───────────► tier.2
```
