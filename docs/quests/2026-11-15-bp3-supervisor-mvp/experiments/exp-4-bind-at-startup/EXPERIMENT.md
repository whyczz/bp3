---
date: 2026-11-15
quest: ../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — bind-at-startup: binding is a fold key, not a ritual

## TL;DR

With the sentinel folding WALs, session <-> Run
binding stops being something hooks beg children to
perform. The launcher names the Run; the fold
derives which session served it from WAL evidence
(run-folder mentions, bp3 invocations, timestamps).
Hooks demote to leaving footprints; the child-typed
prefix retires to explicit override.

## Demo (design trace)

```text
fold(session S) -> commands touch runs/<R>/tape.log; bp3 q u submit by S
derive: S served R   (no prefix typed anywhere in WAL)
```

## Diagram

```text
launcher names R -> child works (any commands)
WAL evidence: runs/<R> paths, bp3 q u calls, pid/session ids
sentinel fold -> binding S<->R (one candidate) 
              -> ambiguous (2+) => bind nothing, warn
```

## Pseudocode

```python
def bind(session, runs):
    cands = [r for r in runs if wal_links(session, r)]
    return cands[0] if len(cands) == 1 else None   # fail closed
```

| Field | Value |
|---|---|
| Intent | startup binding derived, not performed; one correlation path |
| Lane | standard |
| Output | fold-key binding in sentinel; hooks reduced; prefix = override only |
| Depends on | Exp 2, Exp 3 |

## Acceptance (fails today: typed prefix + agent-link claim rituals)

| Case | Expected |
|---|---|
| child never types prefix | binding derived from WAL evidence |
| two Runs plausible | bind nothing; warning names both |
| typed prefix present | override wins over derived candidate |
| pi child | env run-id at spawn; session_start row confirms; same fold key |

## Acceptance test (goal block)

- **Objective:** no child cooperation required for
  a witnessed Run on either engine.
- **Prove by:** toy drives with prefix-free children
  on muse + pi; ambiguity fixture.
- **Done when:** bindings derived in both drives;
  ambiguity binds nothing.

## Tests

known cases: Acceptance table + Exp 1 corpus
re-derived under fold-key binding (5/5 still).
property-based: candidate generation never
invents a binding absent WAL evidence. Demos: both
drives observed.

## Context

This is the canceled quest's Exp 2a lesson applied
with better tools: the join (session, agent, run)
kept failing because it was performed at event time
across two contexts. As a fold over recorded
evidence, all three ids are present at leisure.
