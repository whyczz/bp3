---
date: 2026-11-18
quest: ../../QUEST.md
node: unit.2
status: proposed
---

# unit.2 - clock-seam: one module reads the wall clock

## TL;DR

`src/quest/clock.ml` becomes the only place that calls `Unix.time`
or `Unix.gettimeofday`. All 20 sites today (harness 12, hooks 6,
gitx 1, worktree 1) go through it. Unit tests drive time with a fake
clock, never the machine's clock. Shape (red-ink R4): hybrid. Time
decisions are pure predicates taking `~now`; effectful loops call
`Clock.now ()`; the binary honors no time env var.

## Acceptance gates

Design trace (nothing has run):

```text
$ grep -l 'Unix\.time\|Unix\.gettimeofday' src/quest/*.ml
src/quest/clock.ml

$ dune test
test_clock: case_stale_gate_keeps_a_binding_seen_899_seconds_ago ok
test_clock: case_stale_gate_sweeps_a_binding_seen_901_seconds_ago ok
test_clock: case_compact_ts_formats_epoch_1795000000_as_20261118T110640Z ok
```

```yaml
objective: route every wall-clock read in src/quest through Clock so tests can fix time
prove by:
  - grep -l 'Unix\.time\|Unix\.gettimeofday' src/quest/*.ml    # 4 files today
  - dune test with a fake clock at fixed epochs
  - make check-full (or today's make check) on the result
done when:
  - the grep lists only src/quest/clock.ml
  - stale-gate boundary cases at 899s and 901s pass with a fake clock and no sleep
  - compact_ts and the gitx timestamp format a fixed epoch to a fixed string
  - planted mutation: stale gate uses >= instead of >; a case_ test goes red
  - the full gate is green: no behavior change with the real clock
```

## Diagram

```text
before: harness.ml ─┐                after: harness.ml ─┐
        hooks.ml ───┼─► Unix.time            hooks.ml ───┼─► Clock.now () ─► Unix.gettimeofday
        gitx.ml ────┤                        gitx.ml ────┤        ▲
        worktree.ml ┘                        worktree.ml ┘        │ tests: Clock.with_fixed 1795000000.
```

## Pseudocode

```python
# hybrid (red-ink R4): decisions are pure, loops read the seam
def stale(last_seen, *, now, stale_after_s): return now - last_seen > stale_after_s
def silent(last_output, *, now, silence_s): return now - last_output > silence_s
def past_deadline(deadline, *, now): return now >= deadline

class Clock:                                       # src/quest/clock.ml
    now = staticmethod(time.time)                  # Unix.gettimeofday: sub-second
    @contextmanager
    def with_fixed(t):                             # restores even on failure (Fun.protect)
        old, Clock.now = Clock.now, (lambda: t)
        try: yield
        finally: Clock.now = old

# effectful caller
if stale(b.last_seen_epoch, now=Clock.now(), stale_after_s=900.0): sweep(b)
```

| Field | Value |
|---|---|
| Intent | make time an input, so unit tests are hermetic |
| Lane | standard |
| Output | `src/quest/clock.ml`, 20 call sites rerouted, `test/unit/test_clock.ml` |
| Acceptance | goal block above; fails today (grep lists 4 files) |
| Depends on | unit.1 |
| Tests | known cases: stale boundary at 899s and 901s, `compact_ts` at a fixed epoch; property-based: `law_stale_never_reverts_as_now_grows`; fixture: the full gate unchanged |

## Prose

The 2026-11-18 red chair found the whole-second clock with no seam:
every time-dependent rule (stale gate, silence windows, deadlines,
run-id timestamps) can only be tested by sleeping or by racing the
real clock. That is where the timing flakes come from.

Red-ink R4 settled the shape as hybrid. Decisions (stale, silent,
past deadline) become pure predicates taking `~now`, which matches
the 11-14 rule "the fake clock is an argument". The 12 harness sites
inside effectful loops call `Clock.now ()` instead of threading
`~now` through every caller. A `BP3_NOW` env var was rejected: it
would let anyone forge ledger timestamps. `Clock.with_fixed` restores
the real clock even when a test fails.

`Unix.gettimeofday` gives sub-second time; seam.1 needs it for
run-ids. Switching from `Unix.time` changes nothing for the
second-granularity comparisons.
