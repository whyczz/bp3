---
date: 2026-11-15
quest: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — sentinel-fold: one deriving step, eyes checked first

## TL;DR

The sentinel goes live using Exp 1's proven fold:
on each invocation it discovers Runs, folds WAL +
pid liveness into lifecycle, and reports a trace
per Run. First thing it does is probe its own
inputs — WAL present and carrying the fields the
fold consumes — else `W_SENTINEL_BLIND` and a
fallback to pid + mailbox rows only.

## Demo (design trace)

```text
bp3 q sentinel 2026-11-15-bp3-supervisor-mvp
  probe: pi WAL ok; muse WAL ok
  run ...-submit-c1: running (pid alive, WAL grew 3s ago)
  run ...-review-c1: settled (close marker, exit 0)
warnings: []
```

## Diagram

```text
invocation -> probe WAL sources ──fail──► W_SENTINEL_BLIND
      │ ok                                    (fallback: pid+rows)
      ▼
discover runs (folders + mailboxes + pids)
      │ fold adapter stream + monitor facts
      ▼
lifecycle per Run + trace -> bp3 q r / await callers
```

## Pseudocode

```python
def sentinel(quest):
    health = {h: probe(h) for h in ("pi", "muse")}
    warn([f"W_SENTINEL_BLIND:{h}" for h, ok in health.items() if not ok])
    return [derive(run, fold(run), pid_alive(run)) for run in runs(quest)]
```

| Field | Value |
|---|---|
| Intent | live ephemeral sentinel; lifecycle derivation owned in exactly one place |
| Lane | standard |
| Output | sentinel implementation (home decided at framing: OCaml verb default) + probe |
| Depends on | Exp 1 |

## Acceptance (fails today: no sentinel, no probe)

| Case | Expected |
|---|---|
| healthy logs | lifecycle derived for every discovered Run |
| WAL file deleted | `W_SENTINEL_BLIND` emitted; death still derived by pid |
| WAL reshaped (fields renamed) | probe fails on consumed fields, same warning |
| dead sentinel yesterday | today's invocation re-derives everything; no stale state |

## Acceptance test (goal block)

- **Objective:** lifecycle is derivable on demand,
  and blindness is loud.
- **Prove by:** live drive on a toy quest + a
  sabotaged-WAL variant.
- **Done when:** both drives show derived states;
  sabotage shows the warning and pid-only fallback.

## Tests

known cases: Acceptance table. property-based:
fold is idempotent and order-independent across
repeated invocations. Demos: toy drive + sabotage
drive, observed.

## Context

Exp 1 proved the fold offline. The standing risk is
silent blindness after a harness update; the probe
turns that into a same-day warning in the verdict
surface (`bp3 q r` warnings) and a `sentinel_blind`
mailbox row.
