---
date: 2026-11-16
goal: ../GRAPH.md
exp: mvp.2
status: proposed
---

# mvp.2 - context-resolution: bp3 knows where it is

## TL;DR

After a claim (mvp.1), every bp3 call resolves its
context from the claim store — session-id first,
desk (cwd) second — and stamps graph, node, edge,
and run-id into verdicts and ledger lines. The
child types no graph, no exp, no export ritual.
Env vars survive only as hints that bp3 may
cross-check, never as the store. Unclaimed
invocations behave exactly as today, plus
`W_CONTEXT_UNCLAIMED`.

## Demo (design trace)

```text
child (claimed session): bp3 e handoff --commit …
  -> resolves session -> run-id/edge; ledger line stamped
child (claimed, in desk): bp3 e
  -> prints resolved context + source rung + legal edges, no names typed
stranger shell: bp3 q …
  -> behaves as today + W_CONTEXT_UNCLAIMED
```

## Diagram

```text
bp3 call ─► session-id? ─► by-session index ─► claim {graph,node,edge,run}
              └─► cwd desk? ─► desk context file ─► claim
              └─► none ─► today's behavior + W_CONTEXT_UNCLAIMED
env: hint only, cross-checked, mismatch -> W_CONTEXT_ENV_MISMATCH
```

## Pseudocode

```python
def resolve_context(env, cwd, session_id):
    claim = by_session(session_id) or desk_context(cwd)
    if claim and env.get("BP3_RUN_ID") not in (None, claim.run_id):
        warn("W_CONTEXT_ENV_MISMATCH")
    return claim  # stamps every verdict + ledger line
```

| Field | Value |
|---|---|
| Intent | context is resolved, never carried; the export ritual dies |
| Lane | standard |
| Output | context resolution in the CLI doors; stamped verdicts/ledger |
| Depends on | mvp.1 |

## Acceptance

| Case | Expected |
|---|---|
| claimed session | `bp3` calls with no graph/node arguments resolve and stamp the claimed run-id + edge on verdicts and the handoff ledger line |
| claimed desk, new shell | a fresh shell in the desk (no session-id) resolves via desk context |
| bare `bp3 e` after claim | prints resolved context, source rung, and legal edges; the worker never types graph/node/run-id or exports on any call |
| unclaimed | legacy behavior unchanged, one `W_CONTEXT_UNCLAIMED` warning |
| env disagreement | env naming a different run-id warns `W_CONTEXT_ENV_MISMATCH` and the claim wins |
| desk rung never guesses (red-chair) | when a desk holds more than one live claimed run config and no session rung resolves, resolution refuses (`E_NO_CONTEXT`, facts naming the live run_ids) instead of picking the latest claim |
| no false claim | a session in an unclaimed desk never inherits a sibling node's context (desk context is per-claim, checked against cwd) |
| env-set run-id (standing ruling) | the stamped run-id on grade evidence is the claimed one; hooks witness does not gate |

## Acceptance test (goal block)

- **Objective:** a claimed child drives a full
  edge touching zero context flags and zero
  exports, and the ledger proves it.
- **Prove by:** handoff drive from a claimed
  session + fresh desk shell; ledger line stamps;
  mismatch and unclaimed warning cases.
- **Done when:** the handoff ledger line carries
  the claimed run-id with no env set, observed.

## Tests

Resolution precedence fixtures (session > desk >
none), mismatch warnings, cross-node isolation in
one repo (two desks, two claims, no bleed),
regression: every existing CLI test unchanged in
behavior for unclaimed callers.

## Context

The mvp.1-era ruling made run-id env-set because
flags were worse; env was always a transport, not
a home. The claim store is the home. This exp is
where the brief shrinks to one line in practice:
after claim, the child just works.
