---
date: 2026-11-15
quest: ../QUEST.md
exp: 9
status: proposed
---

# Exp 9 — pi-sentinel-rethink: pi engine, second draft (design)

## TL;DR

Owner-gated design exp. Rethink the pi engine
under the sentinel pattern: which parts of the
canceled pi quest survive (dispatcher, contract),
which the supervisor replaces (binding rituals,
await), and the smallest pi-engine MVP that Exp 10
proves. Output is a decided design, not code.

## Demo (design trace)

```text
before: extension emits + hopes hooks correlate
after:  dispatcher spawns; WAL is pi session file;
        supervisor folds; watch kills; done
```

## Diagram

```text
canceled pi quest ──► keep / replace / drop table
supervisor contract ─┘        │
                              ▼
                    pi-engine MVP design (decided)
```

## Pseudocode

```python
design = decide(keep=[dispatcher, contract],
                replace=[binding, await],
                drop=[...], owner=gate)
```

| Field | Value |
|---|---|
| Intent | pi engine re-founded on the supervisor pattern |
| Lane | standard |
| Output | design record (this file, completed) + Exp 10 brief deltas |
| Depends on | Exp 8 (muse live proof) |

## Acceptance (fails today: pi design is the canceled quest's)

| Case | Expected |
|---|---|
| keep/replace/drop | every canceled-quest component dispositioned with reason |
| MVP shape | Exp 10 runnable as written from the design |
| owner gate | design approved by owner before Exp 10 |

## Acceptance test (goal block)

- **Objective:** a pi MVP design the owner has
  actually approved.
- **Prove by:** this record + owner nod recorded.
- **Done when:** disposition table complete; nod in
  the quest record.

## Tests

design exp: review is the test (red-chair the
design before approval). Demos: before/after flow
traces in this record.

## Context

Teach-before-building rule applies double here:
the canceled quest is the prior art and the
cautionary tale in one.
