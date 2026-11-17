---
date: 2026-11-16
goal: ../GRAPH.md
exp: dogfood.1
status: proposed
---

# dogfood.1 - link-drive: flappy, old brief vs link brief

## TL;DR

The A/B proof. The same flappy node driven twice
per harness: once with yesterday's setup-prose
brief, once with a one-line link brief — plus
seeded setup attacks (duplicate claim, quoting
claimer, wrong-desk claim) that must refuse at
claim time. Acceptance is the metric table, not
the artifact: if the link way does not win on
setup refusals and time-to-first-work, it does
not ship on speed grounds.

## Demo (design trace)

```text
old: brief(setup prose) -> child exports, guesses desk -> work -> submit
link: brief("claim bp3link_x, build flappy") -> claim -> work -> handoff
attacks: claim spent token -> E_LINK_SPENT; claim from wrong desk -> refused
metrics: setup_refusals_at_claim, time_to_first_productive_call,
         brief_chars, cycles_to_land
```

## Diagram

```text
flappy node ─► old brief drive ─► metrics ┐
            └► link brief drive ─► metrics ┴► comparison table (observed)
attacks ─► claim refusals (counted, named)
```

## Pseudocode

```python
for harness in [muse, pi]:
    old = drive(flappy, brief=setup_prose)
    new = drive(flappy, brief=link_line)
    assert new.setup_cycles == 0 and old.setup_cycles >= new.setup_cycles
```

| Field | Value |
|---|---|
| Intent | the link's speed claim becomes measured fact or dies |
| Lane | standard |
| Output | flappy artifacts ×4 (old/link × muse/pi), metric table, attack log |
| Depends on | mvp.1, mvp.2 |

## Acceptance

| Case | Expected |
|---|---|
| both drives land | all four drives produce working flappy artifacts (`node --check` pass) |
| link brief is one line | link-way briefs contain the claim line and the task, no desk/run-id/export prose (diffed against old briefs) |
| attacks refuse at claim | duplicate claim, quoting-session claim, wrong-desk claim each refuse at claim with named errors; zero setup cycles burned |
| metrics observed | setup refusals, time-to-first-productive-call, brief chars, cycles-to-land recorded per drive from tapes/ledger, not estimated |
| supervised proof unchanged | every Run derives its lifecycle via the supervisor fold; claims add no testimony to grades |
| Pi nested tree | on Pi, root session -> node-worker session -> edge-worker session each claim a distinct link; `parent_run_id`/depth reconstruct the tree, and each child dies after its terminal result bubbles upward |
| env-set run-id (standing ruling) | claimed run-id stamped; env-only drive is the "old" arm |

## Acceptance test (goal block)

- **Objective:** prove (or kill) the link's
  experience claim on the toy that exposed the
  old way's costs.
- **Prove by:** four drives + three attacks, all
  metric'd from artifacts.
- **Done when:** the comparison table is filled
  from observed runs, attacks refused at claim,
  observed.

## Tests

The drive is the test. Artifact smoke per arm:
`node --check`. Property: no link-way child call
carries graph/node/run-id arguments after claim
(tape inventory). Serve link-way artifacts for
the owner's comparison.

## Context

dogfood.1 of the supervisor graph needed 6 cycles
for this toy, three of them setup failures. That
ledger is the baseline this exp is graded
against.
