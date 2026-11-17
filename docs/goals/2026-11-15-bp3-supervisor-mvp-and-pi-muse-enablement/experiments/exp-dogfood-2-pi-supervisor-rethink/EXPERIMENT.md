---
date: 2026-11-15
goal: ../GOAL.md
exp: dogfood.2
status: decided
---

# dogfood.2 - pi-supervisor-rethink: pi engine, second draft (design)

## TL;DR

Decided design, owner-approved (cycle 2). The pi
engine is re-founded on the supervisor pattern: the
dispatcher and the engine contract survive, binding
rituals and await are replaced by InitRecord +
bind-tape + watch, and every witness/event/watchdog
duplicate is dropped. The smallest pi-engine MVP
below is already proved at demo scale by dogfood.3
(pi Run derived `finished` from its tape). Output
is this decided design record, not code.

## Demo (observed, dogfood.3)

```text
before: extension emits + hopes hooks correlate
after:  launcher record-init (live pid) -> pi child
        works -> bind-tape -> supervisor folds tape
        -> watch settled / lifecycle finished
observed: dogfood.3 pi Run 20261116T050354Z-demo-pi-gpt-6.1-sol-c1
        derived finished; flappy.html built by pi
```

## Diagram

```text
canceled pi quest ──► keep / replace / drop table
supervisor contract ─┘        │
                              ▼
                    pi-engine MVP design (decided)
                              │
                              ▼
           dogfood.3 demo proved; full drive approved
```

## Pseudocode

```python
design = decide(keep=[dispatcher, contract],
                replace=[binding, await],
                drop=[witness, events_store, ts_fold,
                      dispatcher_watchdog],
                owner=approved_cycle2)
```

| Field | Value |
|---|---|
| Intent | pi engine re-founded on the supervisor pattern |
| Lane | standard |
| Output | design record (this file, completed) + dogfood.3 brief deltas |
| Depends on | dogfood.1 (muse live proof) |

## Decision: the pi-engine MVP (three components)

```text
A) bp3-pi extension (in child, fail-open)
   default(pi): choose face; resolve repo root via
     git common dir, never bare process.cwd()
   session hooks may expose in-process signals to
     the dispatcher, but write no persistent proof
   conductor face: exactly four thin tools
     (spawn_run, await_runs, list_runs, release_desk)
   NEVER: mint/parse run-id, derive lifecycle, write
     settle truth, call bp3 q u, kill, spawn
     grandchildren, widen tools/env, attest gates

B) Dispatcher (in conductor process)
   validateInput (hostile keys refused by name),
   mintRunId, loadRole, prepareDesk, spawn_run
   (semaphore; env incl. effective BP3_MODEL and
   BP3_THINKING), and hand spawn/exit facts to the
   supervisor via record-init / bind-tape. It does
   not own a second watchdog, lifecycle fold, or
   persistent event writer.

C) supervisor (bp3 OCaml, src/quest/harness.ml)
   find-tape, pi session parser, watch (sole
   killer), lifecycle fold, W_SUPERVISOR_BLIND probe.
   Sole writer of:
     <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl
     <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.json (cache)
   Neither A nor B duplicates C.
```

MVP boundary: A+B are the only new pi-side code the
full drive needs; C already exists and is proved
(mvp.1-mvp.3, followup.2-followup.4, dogfood.3).
The MVP ships no daemon: supervisor and watch are
rerunnable invocations, and lifecycle derives from
files + pid, never from an in-memory live set.

## Keep / replace / drop: canceled-quest components

Source: `docs/goals/2026-11-15-pi-engine-conductor/GOAL.md`
(the canceled pi quest). Every component named
there is dispositioned below.

| Component (canceled quest) | Disposition | Reason |
|---|---|---|
| Dispatcher concept (`bp3-pi`, spawn typed children) | keep | Pi has no workflow host; someone must spawn. Supervisor pattern narrows it to spawn + handoff only. |
| Engine output contract (`StepResult`, `RunEventRow`, `Report` shapes) | keep (shapes), replace (store) | Conductor reads `bp3 q r` after the step, never child self-report. Shapes stay; `RunEventRow` is no longer persisted per-Run (see events store row). |
| `SpawnInput` + refused inputs (`BP3_DECIDER`, caller tools/env refused by name) | keep | Hostile-key refusal is the env contract; hardening requires `E_REFUSED_INPUT` naming the key. |
| Role files (`model`/`thinking`/`tools` frontmatter; override beats role, role beats conductor) | keep | Routing must stay visible and gradeable; child never silently inherits conductor model. |
| Run-id as primary key (`<ts>-<edge>-<harness>-<model>-c<cycle>`, opaque to consumers) | keep | Mintable at creation by the owner of the record; session-id stays a witnessed field, never a key. |
| Four conductor tools (`spawn_run`, `await_runs`, `list_runs`, `release_desk`) | keep (names), replace (await/list bodies) | Names survive. `await_runs` becomes a thin call over `bp3 harness watch`; `list_runs` folds `run-lifecycle-derivations`, not an events store. |
| Desk nesting (quest desk + run desks; dirty release refused; orphaned desk listed, released only explicitly) | keep | Parallel quest execution and uncommitted-work safety are structural, not pi-specific. Birth stays inside `spawn_run` / conductor bash; no `init_desk` tool. |
| Conductor skill (reads `bp3 q r`, one step per state, re-reads) | keep | Control flow stays in the conductor; dispatcher outcomes are evidence, the re-read is the verdict. Children call their own `bp3 q u` edges. |
| Settled = process exited AND session idle/closed | replace | Replaced by derived lifecycle: pi `finished` = finish evidence on last whole tape entry (`session_closed`, or final assistant `stopReason: stop`) + no live pid. Process exit alone never finishes; a row alone never finishes a live child. |
| Binding rituals (child hook prefix witness, session-keyed registry) | replace | Replaced by InitRecord-first binding: launcher `record-init` (live pid) before work is observed, `bind-tape` after exit, 1 tape <> 1 run-id pinned (followup.3, followup.4). Pi tapes bind sessions, never Runs (backtest.2 F1), so the binding lives in the derivation log, not the tape. |
| `await_runs` polling / dispatcher settled-wait | replace | Replaced by `bp3 harness watch` (blocking, sole TERM/KILL owner, silence watchdog) + supervisor fold. One killer, one fold. |
| Run event log (`.git/bp3-run-events/<run_id>.jsonl`, TS `events.ts` writer + fold) | drop | Duplicates the supervisor. Sole persisted supervisor output is `run-lifecycle-derivations/`; legacy event logs are read-only migration inputs only. Do not port the writer or the TS fold. |
| Child witness handlers (session_start binding row, heartbeat, `run_started`/`run_settled` appends) | drop | Witness duplicates spawn-side `run_started` and asks the child to prove itself. Extension hooks may signal in-process only; they write no persistent proof. Heartbeat is dropped with it: freshness derives from tape mtime + pid, so the long-tool-call heartbeat gap cannot occur. |
| Dispatcher watchdog (second watchdog in conductor process) | drop | Two watchdogs race. `watch` is the sole killer (TERM -> KILL); supervisor starts watch but never signals a pid itself. |
| Stored lifecycle field / `spawned|running|settled|orphaned` TS fold | drop | Lifecycle is derived, never stored: `init / active / finished / orphaned` folded from InitRecord + tape + pid. The `.json` is a fingerprint-checked disposable cache; deleting it changes nothing except speed. |
| `docs/engine-contract/` schemas + validation unit as a new artifact | drop (for MVP) | GOAL.md records it as a to-build artifact, not an existing authority. Contract shapes above are the MVP contract; schemas return only if a second harness needs them. |
| Tape copy into `runs/<run-id>/` at settle | drop | Tape stays at the pi session source; derivations store pointers only (path, entry id, byte range, digest, pid probe), resolved via `find-tape --entry`. Nobody ingests a whole tape. |

## Settled defects: disposition

From the auto-red-ink addendum; each maps to the
table above or a named MVP rule.

| Defect | Disposition |
|---|---|
| Witness duplicates spawn-side `run_started` | drop witness writer; InitRecord is the only start row |
| `BP3_THINKING` read but never set | keep contract, fix in dispatcher: spawn env carries effective `BP3_MODEL` and `BP3_THINKING` (hardening env-contract test) |
| Repo root bound to child cwd | replace: extension resolves repo root via git common dir, never bare `process.cwd()` |
| Two watchdogs | drop dispatcher watchdog; `watch` sole killer |
| Two writers | drop events writer; supervisor sole writer of derivations |
| Settle-by-row before reap | replace: settle row alone never finishes a live child; closed-but-not-exited suspends silence kill, overall timeout still applies |
| Heartbeat gap during long tool calls | drop heartbeat; freshness = max(tape mtime, latest derivation-observation timestamp) + pid |
| Persistent `events.ts` writer/fold duplicating supervisor | drop; do not port |

## Backtest.2 findings: consumed

Every finding in backtest.2's report appears here
(the addendum's consumer rule).

| Finding | Consumed as |
|---|---|
| F1: pi tapes bind sessions, never Runs; no `BP3_RUN_ID` in 38/38 tapes | replace binding (above): dispatcher/launcher must `record-init` before spawn; Run association exists only via InitRecord. Live again in dogfood.3: `find-tape --run-id` scan needs a literal `BP3_RUN_ID=` mention pi tapes lack; fold/watch honor the binding row, scan resolution does not. MVP keeps binding-row resolution as the primary path. |
| F2: no `session_closed`; clean end is final assistant `stopReason: stop` | keep in adapter: that entry is pi finish evidence (followup.2 `tape_evidence`); torn final entry is `W_TORN_TAIL`, evidence of nothing |
| F3: 3 sessions with neither finish nor refusal (c1/c2/2a indistinguishable in tape alone) | keep as derived truth: without pid/ledger evidence they stay `active`/`orphaned` by freshness + pid, never guessed `finished` |
| F4: usage present corpus-wide; fold sums equal tape sums | keep: usage folds from assistant entries; no witness usage rows needed |
| Incident patterns (c3 settled 33; c1 unwitnessed 3; refusals upper-bound) | failure-mode map below; exact run-id match 0/5 is F1, not an adapter miss |

## Failure modes: named replacement or explicit keep

| Canceled-quest failure mode | MVP answer |
|---|---|
| Unwitnessed (c1: work done, no proof) | InitRecord written by launcher before work + tape fold; child testimony never required |
| Fossilized after submit (c2: submitted, then silent) | Freshness + pid derivation reads `orphaned`; supervisor tick re-reads `bp3 q r` (tell -> watch -> judge -> finalize) |
| Unsettleable (2a: settle attempted, never finished) | `finished` requires finish evidence + dead pid; a settle row alone settles nothing, and a live pid is never `finished` |
| Refusals stopped honestly (2b) | Keep: refusals are `{code, facts}` information; conductor re-reads and reports, never retries blind |
| Second watchdog / two writers | Dropped (above); single killer, single derivation writer |

## dogfood.3 brief deltas

dogfood.3 (demo scope, owner ruling: demos are
experiment Runs, not full inducts) already ran as
written from this design's core: launcher
`record-init` with live pid, pi child builds
`flappy.html`, `bind-tape`, supervisor derives
`finished`, artifact `node --check` passes. No
delta was needed for the demo; it is the cold-reader
evidence that the MVP core is executable.

Deltas this design hands to any future full pi
drive exp (not dogfood.3, which is landed):

1. Build A+B (`bp3-pi` extension + dispatcher) to
   the MVP boundary above; C needs no new code.
2. Drive one toy exp todo -> `exp_fin` with every
   edge called by a spawned pi child; grade matrix
   shape identical to the muse grade.
3. Prove hardening Pi rows on fake-pi fixtures
   (clean, hung, slow-drip, closed-not-exited,
   crash-before-session, malformed-output, child
   self-settle ignored) before the live drive.

## Acceptance

| Case | Expected | Status |
|---|---|---|
| keep/replace/drop | every canceled-quest component dispositioned with reason | done: table above covers dispatcher, contract, inputs, roles, run-id, tools, desks, conductor, settled, binding, await, event log, witness, watchdogs, lifecycle store, contract schemas, tape copy; defects + F1-F4 consumed |
| MVP shape | dogfood.3 runnable as written from the design | done at demo scope: dogfood.3 observed `finished` + artifact from record-init/bind-tape/fold alone |
| owner gate | design approved by owner before dogfood.3 | done: owner approved the design as decided (cycle 2 resume, 2026-11-16); see Owner gate below |

## Owner gate

Owner nod recorded (cycle 2, 2026-11-16). The
owner approved the design as decided: keep the
dispatcher, engine contract, roles, run-id, and
desks; replace settled/binding/await with
InitRecord + bind-tape + `watch` as sole killer;
drop the witness writer, events store, TS fold,
second watchdog, and heartbeat. The ledger
`resume` line for cycle 2 carries this ruling
verbatim. The dogfood.3 demo had already proceeded
under the owner's demo-as-experiment ruling; a
full pi drive (the deltas above) is now approved
to start from this design.

## Acceptance test (goal block)

- **Objective:** a pi MVP design the owner has
  actually approved.
- **Prove by:** this record + owner nod recorded.
- **Done when:** disposition table complete (done);
  nod recorded in this record (done, cycle 2).

## Tests

Design exp: review is the test. Red-chair record:
strongest attack — "the dispatcher is the canceled
quest's witness machinery renamed." Answer: every
duty that made it witness machinery (persistent
proof rows, TS fold, second watchdog, stored
lifecycle) is dropped by name above; what remains
spawns and hands off, and dogfood.3 derived
`finished` with no extension present at all.
Second attack — "binding still depends on the
launcher remembering record-init." Answer: true,
and deliberate: InitRecord-first lookup fails
loudly (`E_NOT_FOUND`) instead of binding the
wrong tape; followup.4 pins 1 tape <> 1 run-id.
Cold-reader test: dogfood.3's brief was executable
from the supervisor contract alone (observed).
Property-based: none — design exp; omitted
deliberately, the red-chair record is the evidence.
Hardening tests for the build this design authorizes:
[TEST-HARDENING.md](../../TEST-HARDENING.md)
(Pi implementation in full).

## Context

Teach-before-building rule applies double here:
the canceled quest is the prior art and the
cautionary tale in one. Its GOAL.md remains the
component inventory this record dispositions; it
is not revived as a build plan.
