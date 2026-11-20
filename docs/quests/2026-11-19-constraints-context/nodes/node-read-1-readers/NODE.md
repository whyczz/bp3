---
date: 2026-11-19
quest: ../../QUEST.md
node: read.1
status: proposed
---

# read.1 - readers: plans and grades check against both files

## TL;DR

The places where a plan or a commit is judged start reading the two
files. `/quest` reads them in research and runs a constraints pass
and a common-sense pass in its red chair. Red-ink's closing red chair
runs the same passes. The `induct-inline` grader treats a new
language, library or surface as an owner decision, never a fix it
can make. CLAUDE.md and AGENTS.md link both files.

## Acceptance gates

Observed today:

```text
$ grep -c -E 'CONSTRAINTS.md|CONTEXT.md' skills/quest/SKILL.md skills/red-ink/SKILL.md skills/induct-inline/SKILL.md CLAUDE.md
skills/quest/SKILL.md:0
skills/red-ink/SKILL.md:0
skills/induct-inline/SKILL.md:0
CLAUDE.md:0
```

Design trace:

```text
/quest step 7, constraints pass: "node rules.9 adds sqlite3 (bash lib)"
  -> not in CONSTRAINTS.md -> /teach pitch to the owner before approval
/quest step 7, common-sense pass: "others keep agent state in files (CONTEXT.md Q2,
  checked 2026-11-19); we keep it in a ledger because ..." -> recorded
grader: commit adds `import "zod"` -> lint red -> needs_fix, owner class:
  "library zod (node) needs owner sign-off" -> conductor stops and reports (yolo: park)
```

```yaml
objective: no plan or commit adds a language, library or surface without the owner
prove by:
  - test/skills.sh assertions, one per rule below, on the source skills
    and their rendered copies (bp3 skills install)
  - grep both links in CLAUDE.md and AGENTS.md; cmp CLAUDE.md AGENTS.md
done when:
  - every rule below has an assertion that fails on today's text and passes after
  - CLAUDE.md and AGENTS.md are identical and link both files
  - make check-full green
```

## Diagram

```text
             CONSTRAINTS.md          CONTEXT.md
                  │                      │
/quest  step 2 ───┼──── read both ───────┤
/quest  step 7 ───┴ constraints pass     └ common-sense pass (90-day re-check)
red-ink settle ─── same two passes in the closing red chair
induct-inline grader ─ outside CONSTRAINTS.md ─► needs_fix, owner class (never mechanical)
CLAUDE.md / AGENTS.md ─ one line linking both
```

## Pseudocode

```python
def constraints_pass(plan):
    for x in plan.adds(language=True, library=True, surface=True):
        if x not in CONSTRAINTS:
            require(owner_signoff(teach_pitch(x)))   # dated row before approval
def common_sense_pass(plan):
    for choice in plan.choices:
        ground = CONTEXT.lookup(choice)              # re-run its search if > 90 days old
        record(choice, ground, why_we_differ(choice, ground))
```

## Tables

| Field | Value |
|---|---|
| Intent | the files are read where decisions are made, not just written |
| Lane | standard (skill change: its own node, quest step 6.6) |
| Output | `skills/quest/SKILL.md`, `skills/red-ink/SKILL.md`, `skills/induct-inline/SKILL.md` and their renders, `test/skills.sh`, `CLAUDE.md`, `AGENTS.md` |
| Acceptance | one assertion per rule; each fails today |
| Depends on | rules.1, rules.2, ctx.1 |

| Rule | Skill | Assertion greps for |
|---|---|---|
| step 2 reads CONSTRAINTS.md and CONTEXT.md | quest | `CONSTRAINTS.md` |
| step 7 constraints pass: an addition outside CONSTRAINTS.md needs a `/teach` pitch and owner words before approval | quest | `constraints pass` |
| step 7 common-sense pass from CONTEXT.md, re-checking claims older than 90 days | quest | `common-sense pass` |
| the closing red chair runs both passes | red-ink | `constraints pass` |
| a commit outside CONSTRAINTS.md is `needs_fix`, owner class, never mechanical; yolo parks it | induct-inline | `owner class` |
| a diff to CONSTRAINTS.md without a dated owner-words row is `needs_fix` | induct-inline | `owner-words row` |

## Prose

The icebox entry listed the readers: quest steps 2 and 7, red-ink
settle, red-chair, and the grader briefs. Two are out of this node.
`red-chair` is a yap skill outside this repo; the common-sense pass
lives in quest and red-ink instead. The `induct` workflow grader
(`skills/induct/workflows/induct-grade.js`) keeps its own contract; the
lint already turns its grade gate red on a violation.

The overlap with `docs/icebox/2026-11-19-yolo-decider.md` settles
here: a constraints finding is never `mechanical` or `yolo`. It always
reaches the owner.
