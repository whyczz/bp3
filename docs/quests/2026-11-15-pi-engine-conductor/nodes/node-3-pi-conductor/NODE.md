---
date: 2026-11-15
goal: ../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — pi-conductor: the induct dance, pi edition

## TL;DR

Roles (author, reviewer, checker, lander) as prompt +
tool-allowlist + model/thinking files. Default cast
(red-ink round 2): conductor and reviewer
`openai/gpt-6-astra` high; author `openai/gpt-6.1-sol`
medium; checker `openai/gpt-6.1-terra` medium; lander
`openai/gpt-6.1-terra` low — judge is never the builder
by default, and no child silently inherits the
conductor's model; the conductor dispatches
one step per `bp3 q r` read, exactly as on muse. The
state reads are the conductor's own bash calls — pi has
no reason to burn an LLM child on `bp3 q r` (a muse-workflow
habit we do not import).

## Diagram

The conductor runs inside the quest desk
(`.bp3/worktrees/<quest>/conductor`, round 4 nesting);
children run in run desks under it. Parallel quests =
parallel quest desks; no conductor ever sits in the
owner's main tree.

```text
pi session (conductor, induct skill, cwd = quest desk)
  bp3 q r <quest>            <- bash, itself
  todo      -> spawn author      -> re-read
  submitted -> spawn reviewer + checker (parallel)
  approved  -> spawn lander      -> re-read: exp_fin
  blocked   -> TUI dialog + inbox (human gate, step 4)
```

## Pseudocode

```python
def conduct(quest):
    while (view := bp3_q_r(quest)).rollup != terminal:
        exp = next_unfinished(view)
        match exp.state:
            "todo":      run_step("author", exp)
            "submitted": parallel(run_step("reviewer", exp),
                                  run_step("checker", exp))
            "approved":  run_step("lander", exp)
            "blocked":   return human_gate(view.inbox)
        # loop re-reads; nothing is remembered across reads
```

| Field | Value |
|---|---|
| Intent | one toy exp travels todo → `exp_fin` entirely inside pi |
| Lane | standard |
| Output | `roles/` (author, reviewer, checker, lander) + conductor procedure notes in the exp-5 skill exp's input; toy drive record under `runs/` |
| Depends on | Exp 2 |

## Acceptance (fails today: no roles, no dispatcher)

| Case | Expected |
|---|---|
| full trip | toy exp `exp-1-hello` reaches `exp_fin`; every ledger line's `harness` reads `pi` |
| child calls the edge | submit/review/check/land lines written by children, not the conductor (ledger `run_id`s match dispatcher results) |
| needs_fix cycle | a seeded bad commit gets `needs_fix`, re-read shows `todo` c2, conductor dispatches the fix cycle without paging (Exp 7 rule, muse parity) |
| blocked bubbles | a seeded decision exp parks; conductor surfaces the inbox and stops — no attestation, no resume attempt |

## Acceptance test (goal block)

- **Objective:** pi conducts one exp through the whole
  FSM honestly.
- **Prove by:** the toy drive; `bp3 q r` before/after;
  ledger read showing `harness: pi` on every line.
- **Done when:** toy at `exp_fin`, blocked toy parked,
  zero conductor-called verdict edges.

## Tests

known cases: Acceptance table · property-based: none —
live drive is the fixture (stated omission) · demos:
the toy drive, observed.

## Context

Muse parity is the spec: same states, same dispatch
table, same blocked gate. Differences are pi-shaped
only: processes instead of workflow children, env
instead of hook-witnessed prefixes, bash reads instead
of read-children. Role model choice is measured here
(cheap reviewer vs strong reviewer on the seeded bad
commit), recorded as numbers, not folklore.
