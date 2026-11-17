---
date: 2026-11-16
goal: ../GRAPH.md
exp: followup.6
status: proposed
---

# followup.6 - pi-dispatcher-complete: await, release, roles, watchdog cases

## TL;DR

Complete dogfood.2's dispatcher: `await_runs` as a
thin call over `bp3 harness watch` (sole killer),
`release_desk` with dirty-refusal, and role files
whose model/thinking reach the child's env
effectively (`BP3_MODEL` / `BP3_THINKING`: override
beats role, role beats conductor). The failure cases
are the point: hung, silent, and closed-not-exited
pi children, each with exactly one killer.

## Demo (design trace)

```text
spawn_run(hung child) ─► await_runs ─► watch: silence ─► TERM ─► KILL
fold: orphaned, never finished
spawn_run(normal child) ─► await_runs ─► settled, lifecycle finished
release_desk(dirty) ─► refused; release_desk(clean) ─► released
```

## Diagram

```text
await_runs ─► bp3 harness watch ──sole TERM/KILL──► pi child
                   │ derivation fold
                   ▼
        settled / timeout / orphaned (never finished on a kill)
roles/*.md ─► effective BP3_MODEL + BP3_THINKING in child env
```

## Pseudocode

```python
def await_runs(ids, timeout, silence):
    return watch(ids, timeout, silence)     # watch kills; dispatcher never signals
def release_desk(desk):
    if dirty(desk): refuse("E_DESK_DIRTY")
    release(desk)
```

| Field | Value |
|---|---|
| Intent | dispatcher's await/release/roles contract, failure cases proved |
| Lane | standard |
| Output | dispatcher completion in `extensions/bp3-pi/`, fake-pi suite |
| Depends on | followup.5 |

## Acceptance

| Case | Expected |
|---|---|
| hung pi child (seeded) | `watch` TERM then KILLs inside budget; Run lands `orphaned`, never `finished`; no other component signals the pid (drive trace) |
| silent child | past `--silence-seconds` the silence watchdog fires; closed-not-exited tape suspends the silence kill while the overall timeout still applies |
| await is thin | `await_runs` outcome is watch's verdict verbatim (settled / timeout); the dispatcher keeps no polling loop, no second watchdog, no lifecycle fold |
| release_desk | dirty desk refused and preserved; clean desk released; orphaned desks are listed, released only explicitly |
| roles reach env | child env carries effective `BP3_MODEL` and `BP3_THINKING`; precedence override > role > conductor is observed in the child's InitRecord/tape, never silently inherited |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment for every Run and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** awaited pi Runs end honestly under
  exactly one killer, and roles visibly route model
  and thinking into the child.
- **Prove by:** the fake-pi suite (clean / hung /
  drip / closed-not-exited / crash / malformed /
  self-settling) plus one real-pi drive per case
  class.
- **Done when:** hung child is `orphaned` by watch
  alone, roles observed in env, observed.

## Tests

Fake-pi suite from TEST-HARDENING.md (Pi
implementation + cross-engine contract table):
clean, hung, drip, closed-not-exited, crash,
malformed, self-settling child. Property-based:
supervisor/watch is the sole killer — no other
component signals a pid in any drive trace; a killed
Run never derives `finished`. Demos: hung-child
drive + role-routing drive, observed.

## Context

TEST-HARDENING.md already specifies these cases;
the canceled quest's failures (two watchdogs,
settle-by-row before reap, heartbeat gap) are the
regressions this exp proves dead. Heartbeat stays
dropped: freshness is tape mtime + pid.
