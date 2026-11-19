---
date: 2026-11-16
goal: ../QUEST.md
exp: followup.5
status: proposed
---

# followup.5 - pi-extension: bp3-pi extension + dispatcher spawn path

## TL;DR

Implement dogfood.2's decided pi MVP, components A+B
(spawn path): a fail-open `bp3-pi` pi extension with
exactly four conductor tools, backed by a dispatcher
that spawns pi children under the supervisor —
`record-init` before work, `bind-tape` after exit,
lifecycle only from the OCaml fold. No witness
writer, no events store, no TS fold, no second
watchdog (dogfood.2 drops, owner-approved).

## Demo (design trace)

```text
pi conductor ─► spawn_run(role=author, prompt=...)
dispatcher: mint run-id ─► bp3 harness record-init (live pid)
  ─► spawn pi child (env: BP3_RUN_ID, BP3_MODEL, BP3_THINKING)
child works, exits ─► bind-tape ─► list_runs folds derivations
observed: child Run lifecycle finished, derived by supervisor
```

## Diagram

```text
A) bp3-pi extension (in pi, fail-open, writes no proof)
     └─ four tools ─► B) dispatcher (spawn + handoff only)
                         └─► bp3 harness record-init/bind-tape
C) supervisor (OCaml, exists) ─► fold ─► finished/orphaned
```

## Pseudocode

```python
def spawn_run(input):
    refuse_hostile(input)            # E_REFUSED_INPUT names the key
    run_id = mint_run_id(edge, "pi", model, cycle)
    bp3("harness record-init", run_id, pid=spawn(input, env))
    on_exit: bp3("harness bind-tape", run_id)
def list_runs(): return fold_derivations()   # never an events store
```

| Field | Value |
|---|---|
| Intent | pi children spawn under supervision via the extension |
| Lane | standard |
| Output | `extensions/bp3-pi/` (extension + dispatcher), tests |
| Depends on | dogfood.2 (decided design), followup.4 (bind resolution) |

## Acceptance

| Case | Expected |
|---|---|
| extension loads, fail-open | pi starts with the extension loaded in a non-bp3 dir and in a bp3 repo; with `bp3` unreachable the session still works and the four tools refuse with a typed error, never a crash |
| four tools, nothing more | `spawn_run`, `await_runs`, `list_runs`, `release_desk` registered; no tool mints/parses run-ids visibly, derives lifecycle, writes settle truth, calls `bp3 q u`, kills, or spawns grandchildren |
| spawn path | `spawn_run` on a trivial prompt: InitRecord names the live pid before the child's first tape entry; after exit, `bind-tape` pins 1 tape <> 1 run-id; `list_runs` shows the Run `finished`, folded from `run-lifecycle-derivations/` |
| hostile inputs refused | `spawn_run` carrying `BP3_DECIDER`, caller-supplied tools/env widening, or a caller run-id is refused `E_REFUSED_INPUT` naming the key |
| no proof writing | the extension and dispatcher write nothing under `run-lifecycle-derivations/`, no ledger, no state; `bp3` (record-init/bind-tape/supervisor) is the only writer |
| repo root | root resolves via git common dir; spawning from a nested subdir binds the same quest as from the root |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment for every Run and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** a pi conductor spawns a supervised
  pi child through the extension, and the supervisor —
  not the child, not the extension — proves it
  finished.
- **Prove by:** the spawn drive, the InitRecord +
  binding rows, and the folded `finished` derivation.
- **Done when:** trivial pi child spawned via
  `spawn_run` derives `finished`, observed.

## Tests

Extension test suite (fake-pi + real-pi smoke):
load/fail-open; tool registration surface; hostile
input refusals by key name; spawn trivial child →
`finished`; spawn from nested subdir → same quest.
Property-based: no file under
`run-lifecycle-derivations/` is written by any
process whose executable is the extension or
dispatcher (trace the drive). Prior art, not ported:
canceled quest's `extensions/bp3-pi/src/{witness,
events}.ts` and its TS fold/watchdog stay dropped
per dogfood.2.

## Context

dogfood.3 proved component C with a hand-driven
`pi -p` spawn. This exp makes that discipline a
product: the launcher's hands become the dispatcher's
code. Prior extension lives in the canceled quest's
desk (`extensions/bp3-pi/`, preserved); reuse shapes
(contract, roles, run-id), not its proof machinery.
