---
date: 2026-11-07
quest: ../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — Tape and hooks

## TL;DR

Every Run leaves a complete tape and a factual ledger with no
screen-scraping: the launcher captures verbatim output with
`tee`, hooks annotate the tape and emit deliberate facts
through `bp3 q u`. Tape is evidence; the ledger is truth;
neither is built from the other.

Status: **proposed, not implemented or verified.** The earlier
record for this exp lives at
[../2026-11-07-tape-hooks.md](../2026-11-07-tape-hooks.md) and
predates the settled design; this record supersedes it where
they differ.

## Demo (design trace — nothing here has run yet)

```text
experiments/parser-fix/runs/20261107T143022Z-submit-muse-code-muse-wonder-1.0-c1/
  tape.log     <- verbatim executor output, crash included
  notes.md     <- authored lessons, committed at settle

ledger line (same Run, through bp3 q u):
  {"ts":"...","edge":"submit","commit":"abc1234","cycle":1,
   "harness":"muse-code","model":"muse-wonder-1.0","bp3_version":"..."}
```

```text
launcher --tee--> experiments/<exp>/runs/<id>/tape.log   (verbatim, always)
hooks ----------> markers into tape (structure)
hooks --bp3 q u-> ledger lines (deliberate facts, at the moment they happen)
tape --X--> ledger        (never parsed into facts)
settled Run: tape + notes.md committed on the exp branch, one commit
```

```python
def run(edge, exp):
    run_id = f"{utc_ts()}-{edge}-{harness}-{model}-c{exp.cycle}"
    with tee(f"experiments/{exp}/runs/{run_id}/tape.log"):
        outcome = execute(edge)              # hooks mark tool/turn boundaries
    bp3_q_u(exp, edge, verdict=outcome)      # facts enter the ledger here
    commit(exp.branch, [tape, notes])        # one commit, at settle
```

| Part | Carries |
|---|---|
| Run id | `<ts>-<edge>-<harness>-<model>-c<cycle>`, UTC compact (`20261107T143022Z-review-muse-code-muse-wonder-1.0-c1`); timestamp gives uniqueness, an existing folder fails fast |
| Tape | verbatim executor output including crashes; zero agent cooperation |
| Hook markers | tool/turn structure inside the tape |
| Hook facts | edge taken, verdict, usage, settled — as ledger lines through `bp3 q <quest> u <exp>` |

| Field | Value |
|---|---|
| Intent | Every run leaves a complete tape and a factual ledger without screen-scraping |
| Lane | standard |
| Output | Tape capture by the launcher; hook annotation + fact emission (Pi bridge extension, Muse settings hooks) |
| Depends on | Exp 2 (the seam owns launching) + Exp 3 (facts land in the FSM ledger) |

## Acceptance (fails today: no tape, no hook events, cost hardcoded null)

| Case | Expected |
|---|---|
| executor killed mid-tool-call | complete tape up to the kill |
| every edge taken by a Run | a ledger line exists, none derived from tape text |
| hooks disabled | tape-only capture, no Run lost |
| two Runs in parallel (`submitted`) | distinct run folders, no counting or allocation |
| settled Run | tape + `notes.md` on the exp branch as one commit |

## Acceptance test (goal block)

- **Objective:** wire launcher `tee` capture and hook fact
  emission so every Run leaves a complete tape and the ledger
  gains facts only through `bp3 q u`.
- **Prove by:** fixtures for every Acceptance case: kill an
  executor mid-tool-call and read the tape; run with hooks
  disabled; run review/check Runs in parallel; settle a Run
  and inspect the exp branch for the single tape commit.
- **Done when:** all cases pass and a text search proves no
  ledger line's contents derive from tape text.

## Context

A run's output used to live in a watched pane and die with
it, so the only record of a four-hour bounce was folklore.
The tape ends that: capture is a launcher property, not a
favor the agent does, and it survives crashes and hook
failures alike. Hooks sit on the other trust level — they
emit facts deliberately, at the moment a fact happens, and
those facts become ledger lines through the same `u` door as
everything else. Keeping the layers apart is the whole
design: the day someone parses tape text into facts, screen
output becomes a state channel, and every formatting change
is a silent state change.

Costs ride this exp too: token/usage markers are what let the
scorecard price a Run instead of hardcoding null.

Edge cases: a Run that never settles leaves its tape
uncommitted — recovery reads the branch, not the worktree, so
an unsettled tape is a local artifact until a later pass
commits it. Run-id collision means two Runs claimed the same
second, edge, harness, model, and cycle: that is a duplicate
dispatch, and failing fast names it instead of merging two
tapes into one folder. Warden consumption of the ledger is
out of scope here (decided: not yet); this exp only produces
the record a warden would later eat.
