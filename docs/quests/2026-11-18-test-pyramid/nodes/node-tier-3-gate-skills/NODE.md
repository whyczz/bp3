---
date: 2026-11-18
quest: ../../QUEST.md
node: tier.3
status: proposed
---

# tier.3 - gate-skills: skills name the right gate

## TL;DR

Skill-change node (quest step 6.6). Today `induct` (4 mentions),
`induct-yolo` (1) and `using-bp3` (1) tell sessions to run `make
check`. After tier.2 that is the inner loop, not the gate. This node
points grade and land at `make check-full`, keeps `make check` for
the author's own loop, re-renders every harness copy, and pins the
wording in `test/skills.sh`.

## Acceptance gates

Observed today:

```text
$ git grep -c 'make check' -- skills
skills/induct-yolo/SKILL.md:1
skills/induct/SKILL.md:4
skills/using-bp3/SKILL.md:1
```

Design trace:

```text
$ git grep -n 'make check-full' -- skills | wc -l    -> 6 or more
$ ./test/skills.sh                                    -> ok (gate wording asserted)
```

```yaml
objective: every skill that grades or lands names make check-full; authors may run make check
prove by:
  - git grep -n 'make check' -- skills .claude/skills .agents/skills .pi/skills
  - ./test/skills.sh with a new assertion for gate wording
  - ./bin/bp3 skills install, then diff the rendered copies
done when:
  - every grade or land instruction in induct, induct-inline, induct-yolo, using-bp3, quest and the induct workflows says make check-full
  - test/skills.sh fails if a grade/land instruction says plain make check
  - rendered copies match their sources (GENERATED notice intact)
  - the owner has read the skill diff
```

## Diagram

```text
skills/<name>/SKILL.md ─edit─► bp3 skills install ─► .claude/ .agents/ .pi/ renders
test/skills.sh: grade/land wording must say check-full ──► fails on regression
```

## Pseudocode

```python
for skill in ["induct", "induct-inline", "induct-yolo", "using-bp3", "quest"]:
    for line in instructions(skill, about=["grade", "land", "verify before handoff"]):
        assert "make check-full" in line
assert rendered_copies_match_sources()
```

| Field | Value |
|---|---|
| Intent | children run the gate that proves the binary works end to end |
| Lane | standard (skill change: own gate) |
| Output | skill sources, renders, `test/skills.sh` assertion |
| Acceptance | goal block above; fails today (skills say make check) |
| Depends on | tier.2 |
| Tests | known cases: `test/skills.sh` gate-wording assertions; property-based: none, by decision: a wording rule over a fixed set of skills |

## Prose

Skills are how child sessions behave, so they change in their own
node with their own test, never folded into a code node. The
wording rule is simple: an author may run `make check` after each
edit; anything that grades, hands off, or lands runs
`make check-full`. The workflows under `skills/induct/workflows/`
are included because the grade child reads its gate from there.
