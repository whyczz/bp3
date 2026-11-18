---
date: 2026-11-15
goal: ../GRAPH.md
exp: 4
status: proposed
---

# Exp 4 — pi-event-log: extension events feed the run event log

## TL;DR

On muse, hooks write what is now named the run event
log (legacy store: `.git/bp3-run-registry.json`, a
session-keyed dict — Exp 1 renames the word, Exp 8
migrates the storage): run started/settled,
usage, lint results. On pi, extension events
(`session_start`, `tool_call`, turn end) are the same
nerve endings in-process. This exp wires them: every pi
Run appends rows to its own event log file
(`.git/bp3-run-events/<run_id>.jsonl`, keyed by
run-id — the primary key), so pi drives
get scorecards and the grade matrix's adherence rows
(env preset, settled, usage) have pi evidence to quote.

## Diagram

```text
pi child process
  session_start -> event log: run_started (run_id from env; harness, model, thinking recorded as fields)
  tool_call     -> event log: lint_checked (on edit/bash, gated)
  turn settled  -> event log: usage_recorded (cumulative input, output, calls)
  session close -> event log: run_settled
conductor read: fold(run_id) == grade evidence
```

## Pseudocode

```python
def on_session_start(ctx):
    if env("BP3_RUN_ID"): events.append(run_started)

def on_turn_end(event):
    events.append(usage_recorded, **event.usage)

def usage_of(run_id):   # conductor / grader read path
    return fold(run_id)  # per-Run file, latest usage row wins
```

| Field | Value |
|---|---|
| Intent | pi Runs are measurable; adherence evidence exists on pi |
| Lane | standard |
| Output | event-log writer in the bp3-pi package (child witness face) + tests; one graded pi exp whose matrix quotes pi event rows |
| Depends on | Exp 2 (Exp 3 for the graded drive) |

## Acceptance (fails today: event log has zero pi rows)

| Case | Expected |
|---|---|
| usage recorded | after one pi child Run, event log holds a usage_recorded row with nonzero token counts for its run_id |
| settled pair | run_started and run_settled both present; a killed child has started, no settled |
| no-env silence | a plain interactive pi session (no BP3_RUN_ID) writes nothing to the event log |
| grade quotes it | exp-2's toy grade matrix adherence rows cite event rows with `harness: pi` |

## Acceptance test (goal block)

- **Objective:** pi Runs leave the same evidence trail
  muse Runs leave.
- **Prove by:** event log diff around one live child;
  the graded toy's matrix.
- **Done when:** event rows present, killed child unpaired,
  interactive session silent.

## Tests

known cases: Acceptance table · property-based:
fold dedupes on (run_id, event); usage rows are cumulative snapshots, latest wins ·
fixtures: fake session events in node tests, one live
child · demos: the event log diff, observed.

## Context

The muse design learned this the hard way: env-preset
evidence lives in the event log, and the legacy shared
registry file raced under parallel Runs (fixed with
per-Run desk files on the muse side; Exp 8 applies
the same per-Run shape to the event log itself). Pi children are processes with
env, so binding is free; the write path still appends
per-Run rows, never rewrites the file whole.
