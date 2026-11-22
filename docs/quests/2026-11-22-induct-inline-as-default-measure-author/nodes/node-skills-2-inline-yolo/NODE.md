---
date: 2026-11-22
quest: ../../QUEST.md
node: skills.2
status: proposed
---

# skills.2 - inline-yolo: induct-inline with no human present (skill node)

## TL;DR

A new skill, `induct-inline-yolo`, runs one quest inline (this session
authors, background subagents grade) under induct-yolo's no-human
rails. It never attests, never takes `resume` or `delete`, and never
promotes or pushes. A blocked node is parked, not paged, and the
quest's other ready nodes keep moving. A stated budget stops new work.
The run ends in a check-in report. Like induct-yolo, it carries rails
only and follows induct-inline's procedure as written.

## Acceptance gates

Observed today:

```text
$ ls skills/induct-inline-yolo           # No such file or directory
$ grep -n induct-inline-yolo bin/bp3      # rc=1 (not in CORE_SKILLS)
```

Design trace:

```text
$ ./test/skills.sh
  skills/induct-inline-yolo/SKILL.md and its renders (.claude, .pi, .agents) exist; frontmatter name induct-inline-yolo
  it names induct-inline's procedure "as written" and has no numbered procedure of its own
  rails: BP3_DECIDER stays unset; never resume or delete; never promote or push; park, never page;
         budget stops new work; check-in report (node_fin, parked with reasons, metrics r readout, desks)
  owner-only calls park: constraints-class needs_fix, scope change, no grader available
  induct-inline and induct-yolo each name induct-inline-yolo; CORE_SKILLS in bin/bp3 lists it
$ ./bin/bp3 skills check                 # fresh renders
```

```yaml
objective: a fresh session can run one quest inline with no human, from the skill alone, and never take an owner call
prove by:
  - add-bp3-skill gates (overlap, stateless test, red chair, trigger checks), recorded in the build notes
  - test/skills.sh new assertions (render and install with BP3_COMPLETIONS_DIR in scratch)
  - make check-full
done when: the assertions pass and fail on master, and the gates' results are in the build notes
```

## Diagram

```text
/induct-inline-yolo <quest> [budget]
   └─ induct-inline procedure, as written (author here, background graders, cast boundary)
        rails:  blocked / owner-class ──> park (stays in the inbox; other ready nodes continue)
                budget spent ──> no new author or grade starts
                never: attest, resume, delete, promote, push, page
   └─ check-in report: node_fin, parked (reason each), metrics r (author.wall_s, active_s, grade wall), desks, next owner decision
```

## Pseudocode

```python
def induct_inline_yolo(quest, budget=None):
    assert os.environ.get("BP3_DECIDER") is None
    for step in induct_inline_steps(quest):                # the procedure as written, not a copy
        if step.needs_owner:                               # blocked, constraints-class, scope, no grader
            park(step.node); continue                      # starves only its dependents
        if budget and budget.spent(): break
        step.run()
    return checkin_report(quest)                           # read from bp3 q r, metrics r, desk list
```

## Tables

| Field | Value |
|---|---|
| Intent | the owner's "yolo" for one inline quest, as a written skill instead of a word in a prompt |
| Lane | micro (skill node, through add-bp3-skill's gates) |
| Output | `skills/induct-inline-yolo/SKILL.md` (new), renders, `bin/bp3` (`CORE_SKILLS`), `skills/induct-inline/SKILL.md` and `skills/induct-yolo/SKILL.md` (one cross-reference each), `test/skills.sh` |
| Acceptance | the skill, its renders and the assertions; fail today (no file) |
| Depends on | skills.1 (it rides induct-inline's new text) |

| Situation | induct-inline | induct-inline-yolo |
|---|---|---|
| node blocked | stop and report the owed decision | park; other ready nodes continue |
| constraints-class `needs_fix` | stop, pitch to the owner (`/teach`) | park |
| no subagent tool | the owner judges | park at `handed_off` (never self-grade) |
| grader runtime | subagent, or pi when the owner names it | subagent; pi only if the invocation names it |
| budget | none | optional (grades or wall minutes); stops new work |
| end | the induct report | the check-in report |

## Prose

The owner has said "yolo" three times this week ("with yolo, e.g. you
can decide the overrides", "Fresh grader, yolo", "Approve, yolo"), and
each time it meant the same thing: don't stop to ask about calls that
aren't the owner's, and park the ones that are. This skill writes that
meaning down so it no longer depends on a prompt.

It takes one quest, not a fleet. Fleets need footprints, a merge order
and parallel conductors, which induct-yolo already has. Inline is one
session, and the "one session per quest" rule from skills.1 would break
under a queue.

It carries no procedure of its own, for the same reason induct-yolo
doesn't: two copies of a procedure drift. test/skills.sh checks that it
names induct-inline's procedure as written and has no numbered steps.

## Tests

Known cases: the skills.sh patterns above, each absent from master's
text, and `bp3 skills check` fresh after install. Property-based:
omitted; skill text has no generator.
