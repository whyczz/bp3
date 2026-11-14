---
date: 2026-11-14
quest: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — Unit backfill for the bp3 q seams

## TL;DR

A QCheck/OUnit suite under `src/quest/test/`, run by
`dune test` inside `make check`, covering exactly the
named seams of the 1,389-line core — two laws, boundary
cases, labeled characterization, nothing more.

Two lanes, settled with the owner (2026-11-14): **known
cases for speed** (named examples: boundaries, golden
strings, the exact refusal shapes — fast to run, fast to
read when red) and **property-based tests for breadth**
(generated inputs searching the combinatorial space:
ledger lines × positions × kinds). Laws for invariants,
examples for boundaries and text; neither lane impersonates
the other.

## Demo (design trace)

```text
$ dune test
... law round-trip: 1000 generated ledger lines, decode(encode(x)) = x   ok
... law event-line invariance: state(ledger) = state(ledger + event lines) ok
... stale gate: 899s survives, 901s swept                                 ok
```

## Shape

```text
src/quest/test/
  dune            (test stanza; libraries qcheck, qcheck-ounit? per switch)
  test_store.ml   fold_ledger, ledger_line round-trip, cycle/state cases
  test_hooks.ml   parse_edge_cycle, env-preset regex, kind mapping, stale gate
  test_render.ml  golden verdict strings per --format (characterization)
```

```python
laws = [
  round_trip:      decode(encode(line)) == line,
  event_invariance: fold(L) == fold(L + event_lines),
]
cases = [stale 899/901, preset first-match-wins, conflicting preset ignored,
         unknown kind -> no line, refused keeps state]
```

| Field | Value |
|---|---|
| Intent | fine-grained regression net under the shell fixtures |
| Lane | standard |
| Output | `src/quest/test/` suite; `make check` runs `dune test` |
| Depends on | Exp 1 (this record demonstrates the standard it sets) |

## Acceptance (fails today: `dune test` runs zero tests)

| Case | Expected |
|---|---|
| round-trip law | generated ledger lines survive encode→decode |
| event-line invariance | folded state identical with/without event lines |
| stale-gate boundary | 899s binding survives a sweep; 901s is swept |
| env-preset regex | first match wins; later conflicting preset ignored |
| characterization | render goldens labeled characterization in test names |
| generator quality | the check child judges the generators can produce nasty lines (empty/absent commits, event lines at head and tail, cycle jumps, unknown kinds) — a timid generator is a `needs_fix`, same as a vacuous assertion |
| gate | `make check` fails if any unit test fails |

## Acceptance test (goal block)

- **Objective:** the named seams obey their laws under
  `dune test`, inside the repo gate.
- **Prove by:** `dune test` output; deliberately break
  one law locally and watch `make check` go red (then
  revert); full `make check` green.
- **Done when:** suite exists, both laws generated (not
  example-only), and the red-for-a-reason check observed.

## Context

The icebox entry feared seam extraction would be needed;
framing research says otherwise — `fold_ledger` takes text
and returns state, `parse_edge_cycle` and `ledger_line`
are pure, the core is 1,389 lines. QCheck 0.91 (with the
OUnit backend) is already in the switch; Alcotest is not,
so no dep pin is taken. The shell fixtures stay exactly
as they are: acceptance above, unit below.

## Tests

unit: this exp is the unit layer · fixtures: existing `test/*.sh` untouched · demos: Demo trace above, observed at landing
