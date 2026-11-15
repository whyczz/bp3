# Acceptance and unit-test hardening

This pass turns every design claim into the smallest
test that can kill it. A claim with no named test is
a hope, not an acceptance row.

```text
unit (pure fold/parser/verdict)
  -> contract (same trace, Muse + Pi adapters)
  -> integration (fake children, files, processes)
  -> acceptance (real toy drives)
  -> grader evidence ladder (code -> events -> raw log)
```

## Global rules

- Tests are declared with the exp, not improvised by
  the author Run mid-flight.
- Every acceptance row names: fixture, command,
  expected verdict/lifecycle, and the file or process
  that must (or must not) exist afterward.
- Golden fixtures are captured before migrations.
- Backtests report denominators and incident counts;
  findings do not gate, but parser crashes fail.
- The child-typed run-id prefix is never required in
  a passing test after mvp.4.

## Supervisor core (mvp.1-mvp.3)

| Unit under test | Cases that must kill it |
|---|---|
| lifecycle fold | init-only; fresh active; stale+alive; stale+dead; finished; settle-row with live pid; no InitRecord; torn final line |
| restart derivation | fold with an empty in-memory set still reads a live child `active` from pid + freshness |
| NDJSON stream | unchanged ticks emit nothing; lifecycle changes emit once; exactly one final verdict; human text never on stdout |
| verdict split | killed Run = `outcome:watchdog_killed`, `lifecycle:orphaned`, `settled:false`; call refusal = `E_*`, never an outcome |
| guarded act | duplicate run -> `E_RUN_EXISTS`; busy desk -> `E_DESK_BUSY`; stale judge re-read prevents a second spawn |
| single killer | supervisor starts watch but never signals a pid itself; watch alone escalates TERM -> KILL |
| settling grace | session closed / settle row present suspends silence kill; overall timeout still applies |
| inputs | both/neither/disagreeing identity flags; duplicate flag; missing value; unknown flag; `--flag=value`; invalid run-id; zero/negative/non-numeric durations |
| blindness | missing log, unreadable log, renamed consumed field -> `warnings:["W_SUPERVISOR_BLIND"]`, pid fallback still works |

## Muse implementation (mvp.2, mvp.4, backtest.1, dogfood.1)

| Unit under test | Cases that must kill it |
|---|---|
| session discovery | unique hit; missing session; two candidates refuse and name both; session-id resolves to exactly one run-id |
| run association | association comes from InitRecord first; no child prefix in transcript; ambiguous evidence binds nothing |
| lifecycle derivation | Muse natural completion -> finished; parent/session disappears + stale log -> orphaned; long quiet tool call is not killed by the passive supervisor |
| format drift | missing close marker or usage field trips the probe warning the same day |
| derivation log | parallel Runs write separate derivation files; repeated observations preserve sequence; legacy run-event stores are read-only imports, never write targets |
| runtime non-interference | supervisor fold never spawns, kills, delays, or rewrites a Muse workflow child |
| grader ladder | matrix cites commit artifacts first; event trace second; raw tape only in discrepancy/audit fixtures |

Required Muse integration drive: one real toy quest
with author + parallel grade Runs; derive every
lifecycle after the workflow returns; kill and rerun
the reader mid-drive and derive the same result.

## Pi implementation (mvp.2, mvp.3, backtest.2, dogfood.2, dogfood.3)

| Unit under test | Cases that must kill it |
|---|---|
| extension face | conductor face registers exactly four thin tools; child face registers witness hooks only; face does not flip merely because `BP3_RUN_ID` leaked |
| env contract | spawn env contains effective `BP3_MODEL` and `BP3_THINKING`; child cannot widen tools/env or pass `BP3_DECIDER` (`E_REFUSED_INPUT` names the key) |
| derivation ownership | Pi extension writes no persistent proof rows; launcher/supervisor writes InitRecord and supervisor owns all derivation appends |
| session parser | header only; usage rows; close by `session_closed`; close by assistant stop reason; truncated tail; foreign JSONL |
| await/watch | clean exit; killed child; slow drip; closed-but-not-exited; missing session file; two session candidates refuse |
| watchdog | silence escalates TERM then KILL; no process remains; killed child never returns `settled:true` |
| dispatcher guards | duplicate run, busy desk, dirty desk release, unknown run, malformed child output |
| lifecycle fold | conductor restart does not orphan live children; usage totals equal session-file sums |

Required Pi fixtures extend the existing fake-pi
set: clean, hung, slow-drip, closed-not-exited,
crash-before-session, malformed-output, and a child
that attempts to write its own settle row (ignored
as proof).

## Cross-engine contract tests

One scenario table executed through both adapters:

| Scenario | Muse expected | Pi expected |
|---|---|---|
| clean completion | finished | finished |
| disappearance/death | orphaned | orphaned |
| long silence | derived stale; no Bp3 kill | watchdog kill -> orphaned |
| blind log | warning + fallback | warning + fallback |
| duplicate spawn attempt | refused by name | refused by name |
| child self-reports success only | not finished without evidence | not finished without evidence |

Equivalent traces must derive identical lifecycle
words even though control owner differs.

## Local derived-log storage (mvp.5)

| Unit under test | Cases that must kill it |
|---|---|
| common-dir resolution | main checkout and linked desk resolve the same `<git-common-dir>/bp3/` store; a worktree `.git` file is never treated as a directory |
| derivation log | lifecycle transitions append once per evidence change; rows carry source path + offset/range + fingerprint + pid probe, never raw session content |
| derived state cache | fingerprint match reads `.json`; changed session size/mtime/digest forces refold; deleted `.json` rebuilds identically |
| atomic snapshot | concurrent readers never see torn JSON; temp+rename only |
| cross-desk read | a Run spawned in a desk reads `active`/`finished` identically from the main checkout |
| legacy conversion | shared dict and legacy run-events -> derivation logs is idempotent; no settled Run invented; legacy snapshot hash recorded before disposal |

## Acceptance proof commands (shape)

Each exp names its real commands at implementation
time; the design fixes their shape now:

```text
make check
bp3 harness <verb> ... --run-id <fixture-run>   # JSON verdict asserted
node --test extensions/bp3-pi/test/            # pi unit/integration
replay --engine muse|pi --corpus <dir>         # denominator + incidents
toy drives (dogfood.1, dogfood.3)                         # observed, not synthetic
```

No exp may cite a synthetic payload as the sole
proof for a live claim. Synthetic fixtures prove
units; observed drives prove the mechanism.
