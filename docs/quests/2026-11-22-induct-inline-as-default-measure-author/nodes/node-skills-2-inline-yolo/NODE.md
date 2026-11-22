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

## Build notes (2026-11-22)

add-bp3-skill's gates, in order:

1. The job, in one sentence: the owner runs one quest inline with no
   human present, and gets a check-in report.
   - Example invocations: `/induct-inline-yolo q1`; "run q1 inline,
     yolo, don't stop to ask"; `/induct-inline-yolo q1 6 grades`.
   - Near-misses: `/induct-yolo q1 q2` (a fleet: induct-yolo);
     `/induct-inline q1` with the owner present (induct-inline); "grade
     this node" (using-bp3).
2. Overlap:
   - induct-yolo runs fleets with workflow children; induct-inline
     needs a human for owner calls.
   - A "yolo" section inside induct-inline could absorb this, but the
     owner asked for its own skill ("i want a induct-inline-yolo skill
     as well").
   - It carries rails only and follows induct-inline as written, as
     induct-yolo does with induct.
3. Stateless: instructions only. The check-in report reads
   `bp3 q r`, `metrics r` and `harness desk list`; no hooks, no daemon.
4. Red chair:
   - The trigger word "yolo" is shared with induct-yolo, and the
     descriptions split it: one quest inline here, several quests
     there.
   - Context tax: 66 lines.
   - No collision with any yap skill name.
   - The "decide what isn't the owner's" rail could overreach. It
     names only the fix-and-recommit and next-attempt calls, and it
     parks everything owner-class.
5. Source: `skills/induct-inline-yolo/SKILL.md`, frontmatter `name`
   equals the directory, no placeholders.
6. Install and verify: `bp3 skills install --harness=all` with
   `BP3_COMPLETIONS_DIR` in scratch (the global `_bp3` is untouched,
   Nov 20 16:26). It wrote `.pi`, `.claude` and `.agents` renders and
   added the `.pi/settings.json` exclusion. `muse skills validate
   .agents/skills/induct-inline-yolo --json`: `valid: true`, zero
   diagnostics. `bp3 skills check` ok.
7. Not verified: a live run of the skill by a fresh session. This
   quest ran its rules by hand.

Other changes:

- `bin/bp3` `CORE_SKILLS` gains induct-inline-yolo.
- induct-inline and induct-yolo each name it. The cross-reference was
  left out of skills.1, so that node named no skill that didn't exist
  yet.
- test/skills.sh: the exact `.pi/settings.json` list in the install
  fixture gains the new exclusion. There are 16 new lines per dir, plus
  the `CORE_SKILLS` line; 411 assertions in all. Every new pattern
  fails on master: no skill file, no cross-references, and no
  `CORE_SKILLS` entry there.
- Mutants, each red then restored (`cmp`):
  - a numbered step added: the no-procedure check;
  - the never-promote rail dropped: its line.
- Cycle 2 (the grader's mechanical fixes):
  - Major: the budget stop, the scope-change park row and the check-in
    report's items had no assertion. Eight more lines per dir, 443 in
    all. Deleting the scope-change row, the budget sentence or the
    desks bullet now turns skills.sh red.
  - Minor: `brief_verbatim` / `brief_edited` aren't in `q r`,
    `metrics r` or `desk list`; only `metrics scrape` emits them. The
    report's sources now name the last scrape's output, and the readout
    line says which item comes from where.
