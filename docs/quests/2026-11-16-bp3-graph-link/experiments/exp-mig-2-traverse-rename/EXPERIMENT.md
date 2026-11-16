---
date: 2026-11-16
quest: ../QUEST.md
exp: mig.2
status: proposed
---

# mig.2 - traverse-rename: conducting skills take graph names

## TL;DR

Early rename of the conducting surface (owner,
2026-11-16): `/induct` and `/induct-quest` become
`/traverse` — the root worker traverses the graph;
the `induct-exp` workflow becomes `node-loop`,
the node worker's loop (the skeleton mvp.3's
`induct-node` grows from). One traversal word for
the root's job, one loop word for the node's.

## Demo (design trace)

```text
before: /induct -> induct-exp.js (todo) + induct-grade.js + quest-land.js
after:  /traverse -> node-loop.js owns the node FSM loop
        (grade/land become phases briefed inside node-loop,
         folded in by mvp.3's induct-node work)
old spellings refuse: /induct unknown skill; induct-exp.js absent
```

## Diagram

```text
/induct, /induct-quest ──► /traverse        (root worker skill)
/induct-quest-no-human ──► /traverse-no-human
induct-exp.js ──────────► node-loop.js      (node worker workflow)
```

## Pseudocode

```python
rename_skill("induct", "traverse"); rename_skill("induct-quest", "traverse")
rename_skill("induct-quest-no-human", "traverse-no-human")
rename_workflow("induct-exp.js", "node-loop.js")   # behavior unchanged in this node
install_all_harnesses(); assert old_names_refuse()
```

| Field | Value |
|---|---|
| Intent | the conducting vocabulary matches the graph design from early in the quest |
| Lane | standard |
| Output | traverse skill family + node-loop workflow, installed all harnesses; old names gone |
| Depends on | mig.1 (briefs already speak handoff/grade) |

## Acceptance

| Case | Expected |
|---|---|
| traverse conducts | `/traverse` drives one fixture node end to end (handoff -> grade -> land) in a smoke drive |
| node-loop runs | `node-loop.js` executes the todo-node path identically to the old induct-exp on fixtures (behavior-preserving rename; loop generalization is mvp.3) |
| old names refuse | `/induct`, `/induct-quest`, `induct-exp` resolve nowhere (skills dirs + workflows dirs, all harnesses) |
| renders clean | `bp3 skills install --harness=all` regenerates every harness copy; validator green; no hand-edited render |
| no-human variant | `/traverse-no-human` renamed alongside, same gates |

## Acceptance test (goal block)

- **Objective:** the quest conducts itself with
  the new names from this node on.
- **Prove by:** smoke drive under `/traverse`,
  workflow fixture parity, old-name refusal sweep.
- **Done when:** one node conducted under the new
  names, old names resolve nowhere, observed.

## Tests

Known cases: rename sweep (old spellings zero in
skills/workflows/renders), install assertions per
harness, workflow fixture parity pre/post rename.

Property-based: omitted — rename is a bijection;
the sweep + parity cases carry it (stated
decision).

## Context

Owner call at adoption time: the graph vocabulary
should not wait until rename.1 for the conducting
surface the quest itself uses daily. The noun/door
rename (`bp3 g`, `bp3g`) still waits — traverse
conducts over `bp3 q` until mvp.2/rename.1 land.
