---
date: 2026-11-16
quest: ../QUEST.md
exp: followup.2
status: proposed
---

# followup.2 - workflow-birth: renders must track workflow sources

## TL;DR

Papercut found live (mvp.1 grade, owner chose
fix path A): mvp.1 migrated the traverse workflow
sources on the quest branch (children now birth
via `link mint`), but the quest desk's installed
renders (`.agents/workflows/*.js`) were never
regenerated. The grade workflow launched from a
stale render called the retired `record-init`
and refused `E_RETIRED` before its audit child —
no matrix, on a finished product.

The desk render regeneration fixed it by hand
(`bp3 skills install` in the desk; grade then
approved). Make it structural: a dispatch must
never launch a render older than its source.

## Demo (design trace)

```text
before: quest branch takes workflow-source change (child commit)
  -> desk .agents/workflows/induct-grade.js still calls record-init
  -> grade dispatch -> record-init refused E_RETIRED, no audit

after:  dispatch-time check: render hash vs source hash
  -> stale -> re-render in desk (or refuse E_RENDER_STALE naming the file)
  -> grade launches the migrated workflow; mvp.1 grades on merits
```

## Diagram

```text
workflow source (skills/traverse/workflows)
      | bp3 skills install
      v
desk render (.agents/workflows) --hash check at dispatch--> launch
      stale ---------------------> re-render / E_RENDER_STALE
```

## Pseudocode

```python
def dispatch(workflow, desk, args):
    src = source_of(workflow); render = desk_render(desk, workflow)
    if hash(render) != render_hash(src):
        install_skills(desk)              # or refuse, naming render+source
        assert hash(desk_render(desk, workflow)) == render_hash(src)
    launch(desk_render(desk, workflow), args)
```

| Field | Value |
|---|---|
| Intent | the conducting surface that runs is the surface that was written |
| Lane | standard |
| Output | dispatch-time render freshness (re-render or `E_RENDER_STALE`); traverse skill states the rule; regression fixture |
| Depends on | mig.2, mvp.1 (the live papercut) |

## Acceptance

| Case | Expected |
|---|---|
| stale render at dispatch | dispatch re-renders in the desk (or refuses `E_RENDER_STALE` naming render and source); it never launches the stale script |
| mvp.1 replay | with a deliberately staled grade render, the mvp.1 grade scenario reaches the audit child (no `E_RETIRED` pre-audit refusal) |
| fresh render | hash check passes silently; no reinstall cost on the happy path |
| all three workflows | node-loop, induct-grade, quest-land all covered by the same freshness rule |

## Acceptance test (goal block)

- **Objective:** a stale desk render can never
  silently conduct a step again.
- **Prove by:** fixture desk with a backdated
  render; dispatch each workflow kind; observe
  re-render/refusal and successful audit reach.
- **Done when:** stale renders are caught at
  dispatch for all three workflows, observed.

## Tests

Known cases: stale grade render (mvp.1 replay
shape), stale node-loop, stale quest-land, fresh
render no-op.

Property-based: for any source edit, the launched
script's hash equals the current render of that
source (dispatch invariant).

## Context

Owner chose path A at the mvp.1 gate (patch now,
formalize as followup). The manual desk re-render
unblocked mvp.1's grade the same day; this node
makes the freshness structural so the next
workflow-source migration (mvp.3's node-loop
generalization is the obvious candidate) cannot
repeat it.
