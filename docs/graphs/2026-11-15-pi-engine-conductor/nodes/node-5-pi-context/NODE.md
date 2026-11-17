---
date: 2026-11-15
goal: ../GRAPH.md
exp: 5
status: proposed
---

# Exp 5 — pi-context: cold children, forked fixes, a conductor that re-reads

## TL;DR

Pi sessions are JSONL trees with `/tree`, `/fork`, and
extension-customizable compaction — real context
machinery muse workflows don't have. Rules settled
here: step children start cold (fresh session, role
prompt only); fix cycles fork the reviewer session so
the named fix rides in context; the conductor survives
its own compaction by rule — every dispatch is preceded
by a fresh `bp3 q r`, and nothing (merge order, inbox,
budget) is carried in conductor memory.

## Diagram

```text
author child     : cold session
reviewer child   : cold session, bound commit only
needs_fix -> author c2: --fork <reviewer session>
             (fix context inherited, state re-read fresh)
conductor        : long session, compacts freely;
                   truth = bp3 q r, never recall
```

## Pseudocode

```python
def provision(step, exp, cycle, fix=None):
    if step == "author" and cycle > 1:
        return fork(reviewer_session(exp, cycle - 1),
                    prompt=fix.named_fix_verbatim)
    return cold(role_prompt(step))
```

| Field | Value |
|---|---|
| Intent | context is provisioned per step kind, on evidence |
| Lane | standard |
| Output | provisioning rules in role files + dispatcher flags; a measured cold-vs-fork fix-cycle comparison on the seeded bad commit |
| Depends on | Exp 3 |

## Acceptance (fails today: no provisioning exists)

| Case | Expected |
|---|---|
| cold author | c1 author session file contains the role prompt and the exp record, no prior-session entries |
| forked fix | c2 author session's parent chain includes the reviewer session; the named fix text appears verbatim in its first prompt |
| compaction amnesia test | conductor session force-compacted mid-drive (`/compact`), then re-reads and dispatches the correct next step for every exp state |
| no tape parsing | grep of conductor procedure: state decisions cite `bp3 q r` output only |

## Acceptance test (goal block)

- **Objective:** context choices are rules with
  receipts, not vibes.
- **Prove by:** session files of the exp-2 toy drive
  re-run under these rules; the compaction test live.
- **Done when:** fork chain visible in the c2 session
  tree, compacted conductor drives correctly.

## Tests

known cases: Acceptance table · property-based: none —
session-tree inspection is the fixture (stated
omission) · demos: the compaction test, observed.

## Context

Pi's branch summarization (summarize the branch you
leave, inject into the new one) is the tempting extra;
it earns a place only if the forked fix measurably
beats cold-with-fix-pasted. Both are run on the same
seeded bad commit; tokens and verdict recorded either
way. The conductor rule mirrors the no-human skill's
dawn-report discipline: reports from reads, never from
memory.
