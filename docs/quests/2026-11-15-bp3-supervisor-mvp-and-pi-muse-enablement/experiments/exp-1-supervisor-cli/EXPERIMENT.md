---
date: 2026-11-15
quest: ../QUEST.md
exp: 1
status: proposed
---

# Exp 1 — supervisor-cli: the game loop

## TL;DR

`bp3 harness supervisor` exists: one OCaml loop in
the binary (not a shell script) that ticks — fold
Run evidence, derive lifecycle, act (dispatch,
watch, kill, surface) — until the quest is done,
a timeout fires, or a human gate opens.

## Demo (design trace)

```text
bp3 harness supervisor --quest toy --timeout 30m
  tick: A running / B settled / C silent 601s -> KILL
  exit: done (all settled) | timeout | human gate
```

## Diagram

```text
        ┌────────────── tick ──────────────┐
        ▼                                  │
  fold WAL+pid ─► derive lifecycle ─► act ─┘
        exit: all settled | timeout | blocked inbox non-empty
```

## Pseudocode

```python
def supervisor(quest, timeout):
    while not expired(timeout):
        view = fold_all(quest)
        if terminal(view): return Done(view)
        if view.inbox:     return HumanGate(view.inbox)
        act(next_step(view))          # spawn / watch / kill
        sleep(tick)
```

| Field | Value |
|---|---|
| Intent | the loop as CLI path; single deriving/acting rhythm |
| Lane | standard |
| Output | `bp3 harness supervisor` (OCaml) + tick/exit semantics |
| Depends on | none |

## Acceptance (fails today: no harness door, no loop)

| Case | Expected |
|---|---|
| toy quest, all settle | loop exits `done` without LLM polling |
| child never settles | timeout exit, orphans named |
| blocked exp appears | loop exits at human gate with inbox |

## Acceptance test (goal block)

- **Objective:** a loop that babysits Runs
  mechanically and stops for exactly three reasons.
- **Prove by:** toy quest drive with one slow and
  one hung child.
- **Done when:** exits observed for done + timeout
  + gate paths.

## Tests

known cases: Acceptance table (fake children).
property-based: tick is idempotent — same fold,
same action. Demos: toy drive observed.

## Context

Game-engine shape per owner: fixed tick, state
derived per frame, no event callbacks trusted.
The loop is one invocation; killing and rerunning
it loses nothing (all state is folded).
