---
date: 2026-11-16
quest: ../QUEST.md
exp: rename.1
status: proposed
---

# rename.1 - bp3g-rename: every live surface speaks graph

## TL;DR

Last step, full rename (owner-approved
2026-11-16, superseding the naming skill's
standing vocabulary — that skill is updated here
too). CLI: `bp3 g` door for graphs and nodes,
retiring `bp3 q` and quest/exp wording on live
surfaces. Skills: the conducting family becomes
`bp3g` (`/bp3g` conducts a graph; framing and
no-human variants take bp3g- names) because bare
"goal" collides across harnesses; G stands for
goal and graph. Launcher workflows, templates,
and active docs migrate in the same change.
Landed quests' ledger text is history and stays
untouched.

## Demo (design trace)

```text
before: bp3 q <quest> r exp-… ; /induct the quest
after:  bp3 g <graph> r <node> ; /bp3g the graph
grep live surfaces for quest|exp (outside history) -> 0 hits
```

## Diagram

```text
CLI door ─┐
skills ───┼─► one rename commit series ─► installs re-rendered
workflows ┤    (bp3g family)                 all harnesses
templates ┘
landed ledger text: frozen, excluded by path
```

## Pseudocode

```python
SURFACES = [cli_strings, skills_src, workflows, templates, active_docs]
for term in [quest, exp, invoke]:
    assert grep(term, SURFACES, exclude=landed_history) == 0
assert bp3_g_roundtrip() and bp3g_skill_conducts_one_node()
```

| Field | Value |
|---|---|
| Intent | one vocabulary everywhere the system is alive |
| Lane | high-blast-radius |
| Output | renamed CLI + bp3g skill family + migrated live surfaces; surface-count report |
| Depends on | dogfood.2 (rename is last) |

## Acceptance

| Case | Expected |
|---|---|
| `bp3 g` is the door | graph/node create-read-update-delete round-trips through `bp3 g`; state survives the rename (same refs folded, no state rewrite) |
| old door gone | `bp3 q` refuses as unknown door on live surfaces (no silent synonym left behind) |
| bp3g skills conduct | `/bp3g` family installed for all harnesses; one node conducted end to end by the renamed skill in a smoke drive |
| vocabulary zero | grep for quest/exp/invoke terms over CLI strings, skills, workflows, templates, active docs: zero outside frozen history paths (listed explicitly) |
| naming skill updated | the naming skill's vocabulary section teaches graph/node/state/edge/dep and bp3g, same change |
| history frozen | no landed ledger.jsonl or run artifact modified (diff by path allowlist) |

## Acceptance test (goal block)

- **Objective:** after this exp, a newcomer meets
  only the graph vocabulary on any live surface.
- **Prove by:** `bp3 g` round-trip, smoke
  conduction by `/bp3g`, grep surface report,
  history-path diff.
- **Done when:** zero old terms live, graph
  conducts, history untouched, observed.

## Tests

Full `make check` plus: CLI rename fixtures
(old strings absent), skills render/install
assertions for every harness, workflow tests
updated to `bp3 g`. Property: state refs folded
before and after rename produce identical
rollups for an existing graph.

## Context

Names harden into paths, ledger fields, and the
words sessions think in — the supervisor quest's
own records showed the cost of drift (stale
rendered workflows vs source). Rename is last so
the machinery being renamed is final, and total
so no synonym survives to drift again.
