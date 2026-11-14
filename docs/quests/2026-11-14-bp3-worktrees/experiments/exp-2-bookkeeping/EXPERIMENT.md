---
date: 2026-11-14
quest: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — Worktree bookkeeping layer

## TL;DR

The machine-local registry keyed by `run_id`, plus the
public verb composition on top of Exp 1's primitives:
`prepare` (idempotent, records the desk), `check`,
`exit`, `release`, `list` — including the `--path`
override, recorded under the same Run ID. Release
deletes the record; there is no tombstone.

## Demo (design trace)

```text
$ ./bin/bp3 worktree prepare <q> <e> --run R1
{"ok":true,"path":".bp3/worktrees/<q>/<e>/R1","ref":"bp3/exp/<q>/<e>"}
$ ./bin/bp3 worktree prepare <q> <e> --run R1        # resumed child
{"ok":true,"existing":true,"path":".bp3/worktrees/<q>/<e>/R1", ...}
$ ./bin/bp3 worktree prepare <q> <e> --run R2 --path /scratch/wt
{"ok":true,"path":"/scratch/wt", ...}                 # check --run R2 still finds it
$ ./bin/bp3 worktree list
{"ok":true,"worktrees":[{run_id, quest, exp, path, dirty, stale_s}]}
```

## Diagram

```text
prepare ─► util.create ─► registry[run_id] = {quest, exp, path, ref, created_ts}
check   ─► registry[run_id] + util.inspect (live) ─► verdict
exit    ─► cwd -> registry ─► check ─► util.remove ─► delete registry[run_id]
release ─► registry[run_id] ─► util.remove ─► delete registry[run_id]
list    ─► all records + util.inspect each + fs scan (orphans)
```

## Pseudocode

```python
def prepare(quest, exp, run_id, commit=None, path=None):
    if r := registry.get(run_id): return verdict(existing=True, **r)
    path = path or derive(quest, exp, run_id)
    util.create(path, commit or exp_branch(quest, exp))
    registry[run_id] = record(quest, exp, path, ref, now())
    return verdict(path=path)

def release(run_id, force=False):
    util.remove(registry[run_id].path, force)   # primitive refuses dirty
    del registry[run_id]                        # no tombstone (Round 4)
```

| Field | Value |
|---|---|
| Intent | one Run ID finds its worktree, wherever it physically is |
| Lane | standard |
| Output | registry in `.bp3/` (machine-local, gitignored); five public verbs on `bp3 worktree` |
| Depends on | Exp 1 |

## Acceptance (fails today: no registry, no verbs)

| Case | Expected |
|---|---|
| prepare twice, same Run ID | second returns `existing: true`, same path; one worktree |
| prepare `--path` override | later `check`/`release` by Run ID find the override path |
| check | `{dirty, ref, stale_s}`; dirty/stale recomputed live, never stored |
| exit from inside a dirty worktree | `E_DIRTY_TREE`; worktree and record intact |
| exit clean | worktree removed, record deleted, conductor path printed |
| list | every record plus orphan worktrees (on disk, no record) flagged |
| registry after release | Run ID absent — no tombstone rows accumulate |

## Acceptance test (goal block)

- **Objective:** Run ID is the only handle a caller
  needs for the whole worktree lifecycle.
- **Prove by:** `test/worktree.sh` bookkeeping cases in
  a scratch repo, including crash-resume (prepare twice)
  and override addressing.
- **Done when:** all cases pass and no verb accepts a
  raw path as its primary input.

## Tests

known cases: the Acceptance table · property-based:
registry keys are exactly the live worktree set after
any generated prepare/release sequence (no leaks, no
phantoms) · fixtures: scratch-repo suite shared with
Exp 1 · demos: Demo trace, observed at landing.

## Context

Layer 2 of the settled split. The override exists
because Round 2's pure derivation cannot survive a
caller-chosen path — so bookkeeping remembers exactly
one fact per Run that cannot be derived, and everything
else stays live-read. Released records are deleted
(Round 4): the Run's history already lives in ledger,
run folder, and tape.
