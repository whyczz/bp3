---
date: 2026-11-15
goal: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — pi-step-runner: one child process per Run, honestly settled

## TL;DR

A pi extension (ours, TypeScript, in-repo) that spawns one
real `pi` child process per Run: role prompt, tool
allowlist, desk as cwd, identity in env. Returns a typed
result. Settled means process exited AND session closed —
never the child's say-so. Designs plucked from
pi-subagents (typed yields, concurrency semaphore) and
omp (worktree-per-child); neither adopted.

## Demo (design trace)

```text
spawn_run(role=author, quest=Q, exp=E, cycle=1)
  desk = bp3 worktree derive Q E <run-id>; prepare
  child: pi -p --mode json --model <role model>
         --tools read,write,edit,bash --skill <role prompt>
         cwd=desk, env={BP3_RUN_ID, BP3_QUEST, BP3_EXP,
                        BP3_HARNESS=pi, BP3_MODEL}
  -> { run_id, pid, session_file }
await_runs([run_id])
  -> { outcome: exited, exit_code, session_closed: true,
       usage: {input, output, calls} }
```

## Pseudocode

```python
def spawn_run(role, quest, exp, cycle):
    run_id = f"{ts()}-{role.edge}-pi-{model}-c{cycle}"
    desk = worktree_prepare(quest, exp, run_id)   # refuses if live
    proc = pi_child(role, cwd=desk, env=env_preset(run_id, quest, exp))
    events.append(run_started, pid=proc.pid)
    return Run(run_id, proc)

def await_runs(runs):
    code = run.proc.wait()
    closed = session_idle(run.session_file)       # tail event, not exit
    return {run_id, exit_code: code, settled: closed,
            usage: session_usage(run.session_file)}
```

| Field | Value |
|---|---|
| Intent | the primitive every later exp stands on: spawn, fence, reap |
| Lane | standard (new TS extension + tests) |
| Output | `extensions/bp3-pi/` (the `bp3-pi` pi package; concept word: dispatcher) (name settled here) + node tests; pluck/reject notes vs pi-subagents and omp recorded in this record at build time |
| Depends on | Exp 1 (rename first; born speaking the new word) |

## Acceptance (fails today: `~/.pi/agent/extensions/` is empty)

| Case | Expected |
|---|---|
| spawn one child | child pi process runs in its desk with envPreset visible (`env` output in tape shows BP3_RUN_ID) |
| settled honesty | a child killed mid-work reports `settled: false` / nonzero, never success |
| typed result | spawn/wait return the JSON shapes above; malformed child output is an error, not a guess |
| desk fence | second live spawn into the same desk is refused by name |
| concurrency cap | N spawns beyond the cap queue; cap is a named constant, tested |
| usage | result carries token/call counts read from the child's session file |

## Acceptance test (goal block)

- **Objective:** one Run can be spawned, watched, and
  believed.
- **Prove by:** node tests for the dispatcher + one live
  spawn of a toy child that prints its env and exits;
  one killed child.
- **Done when:** tests green and the killed child reads
  as unsettled in the result, not as done.

## Tests

known cases: the Acceptance table · property-based:
run-id derivation (unique per quest/exp/cycle/ts) ·
fixtures: fake `pi` shim on PATH for tests, one real-pi
smoke · demos: the live spawn above, observed at build.

## Context

Pi's own example subagent extension spawns pi processes;
pi-subagents adds chains and a semaphore; omp's `task`
adds worktree isolation and schema-validated yields.
Ours is deliberately smaller: bp3 already owns state,
grading, and landing — the runner only spawns and tells
the truth about settling. RPC mode is the rejected
alternative until `-p --mode json` proves insufficient
(attack 4 in the Quest red chair).
