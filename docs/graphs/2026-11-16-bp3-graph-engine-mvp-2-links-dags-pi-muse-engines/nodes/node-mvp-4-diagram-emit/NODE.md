---
date: 2026-11-16
goal: ../GRAPH.md
exp: mvp.4
status: proposed
---

# mvp.4 - diagram-emit: the graph draws itself

## TL;DR

From a live rollup, emit the graph diagram in
ASCII (terminals, tapes, records) and mermaid
(rendered docs): nodes annotated with state and
cycle, deps grouped into ready-set waves, blocked nodes
naming what they starve, landed nodes marked
`exp_fin`-equivalent in the new vocabulary.
Generated every time — hand-drawn diagrams rot.

## Demo (design trace)

```text
bp3 <door> <graph> diagram --format ascii
  A(landed) ─dep─► C(handed_off c2)
  B(blocked) ─dep─► D(todo, starved by B)

bp3 <door> <graph> diagram --format mermaid
  graph LR ... (same facts, mermaid source)
```

## Diagram

```text
rollup (ledger fold) ─► layering (mvp.3) ─► ascii emitter
                                        └─► mermaid emitter
```

## Pseudocode

```python
def diagram(graph, fmt):
    view = rollup(graph)           # states, cycles, starved sets
    layers = ready-set waves(view.nodes)   # mvp.3
    return emit_ascii(layers, view) if fmt == "ascii" else emit_mermaid(layers, view)
```

| Field | Value |
|---|---|
| Intent | structure is visible at a glance, always current |
| Lane | micro |
| Output | diagram verb with ascii + mermaid formats |
| Depends on | mvp.3 |

## Acceptance

| Case | Expected |
|---|---|
| ascii current | output reflects live states/cycles at call time; rerunning after a node moves changes exactly that node |
| mermaid equivalent | mermaid source carries the same nodes, deps, states as the ascii of the same moment |
| ready-set waves + starvation | ready-set layers visible; a blocked node's starved dependents named on both formats |
| honest labels | generated output states it is generated from live state with the rollup timestamp |

## Acceptance test (goal block)

- **Objective:** anyone can see the graph's
  shape and status without reading ledgers.
- **Prove by:** run both formats against the
  fixture graphs of mvp.3 and one live graph;
  diff facts between formats.
- **Done when:** both formats match the rollup
  facts exactly, observed.

## Tests

Golden fixtures per graph shape; property: every
node and dep in the rollup appears exactly once
per format; state annotation equals fold output.

## Context

The design sessions kept redrawing this diagram
by hand (states at rest, edges as subagents).
Generated diagrams make the convention
self-documenting and give blocked gates a picture
worth paging with.
