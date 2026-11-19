---
date: 2026-11-18
quest: ../../QUEST.md
node: seam.2
status: proposed
---

# seam.2 - listruns-nowait: a snapshot never blocks

## TL;DR

`listRuns` in the bp3-pi extension calls `bp3 harness watch
--timeout-seconds 5` once per run, so every live run costs up to 5s
(`dispatcher.ts:302`). This node adds `bp3 harness watch --once`, which
folds the run's current lifecycle and returns at once without ever
sending TERM or KILL, and points `listRuns` at it.

## Acceptance gates

Observed today:

```text
$ bp3 harness watch --once
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown flag: --once"}, ...}}
```

Design trace:

```text
$ bp3 harness watch --run-id r1 --once
{"ok":true,"run_id":"r1","lifecycle":"running","once":true}
listRuns("toy") over 3 live runs -> 3 rows in 0.09s
```

```yaml
objective: list pi runs with their lifecycle without waiting on any of them
prove by:
  - bp3 harness watch --run-id <id> --once          # E_USAGE today
  - listRuns over 3 live (never-finishing) fake runs, timed
  - a live run's process after a --once call
done when:
  - watch --once returns the same lifecycle word a blocking watch would report at that instant
  - listRuns over 3 live runs returns in under 1s
  - --once never sends a signal: the live run's process is still alive afterwards
  - bp3 harness watch -h documents --once
```

## Diagram

```text
before: listRuns ─► for run: watch --timeout-seconds 5 ─► blocks <= 5s each
after:  listRuns ─► for run: watch --once ─► fold now, print, exit   (no TERM/KILL)
```

## Pseudocode

```python
def watch(run_id, once=False, timeout_s=1800, silence_s=600):
    if once:
        return print_verdict(fold_lifecycle(run_id), once=True)   # read-only snapshot
    return blocking_watch(run_id, timeout_s, silence_s)            # unchanged
```

| Field | Value |
|---|---|
| Intent | remove a per-run 5s wait from run listing |
| Lane | standard |
| Output | `--once` flag in `harness.ml` watch; `dispatcher.ts` listRuns change; help text |
| Acceptance | goal block above; fails today (`--once` is an unknown flag) |
| Depends on | none |
| Tests | known cases: `--once` against live, landed and blocked fake runs (fixture), and listRuns timing via js.1; property-based: none, by decision: one read-only flag over the existing lifecycle fold |

## Prose

The blocking watch is the sole owner of TERM and KILL for a run;
`--once` must not become a second one. It reads and folds, then
exits. The bp3-pi test suite calls `listRuns` three times
(`bp3-pi.test.mjs` lines 138, 173, 296). How much of its 22s goes to
these waits is unmeasured; js.1 measures it and depends on this node.

The extension comment says "lifecycle words come only from bp3".
`--once` keeps that rule: the extension still folds nothing itself.
