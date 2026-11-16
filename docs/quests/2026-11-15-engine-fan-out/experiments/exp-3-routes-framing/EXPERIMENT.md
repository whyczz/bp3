---
date: 2026-11-15
quest: ../../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — Routes framing: `/quest` writes `exp_routes.json`

## TL;DR

Framing gains a question it asks like acceptance: "which
of these exps may run at the same time?" `/quest` writes
`exp_routes.json` beside `QUEST.md` — stages in railway
order, each exp's declared `paths` copied from its exp
record's Output (one source, written twice by the same
hand at the same moment, asserted equal by a fixture) —
with `status: proposed` for the owner's approval edit.
Default when the owner doesn't group: one exp per stage,
which is exactly today's serial railway, so a framed
quest pays nothing for the mechanism until it groups.
Exp records name their stage in their tables. Skill
changes ride as their own exp (quest skill 6.6): this
is that exp — `skills/quest` text and the exp record
shape change here, never inline during another exp.

## Demo (design trace)

```text
framing a 5-exp quest, owner groups exps 1+2 and 4+5:
docs/quests/<q>/exp_routes.json
{ "quest": "<q>", "status": "proposed",
  "stages": [ {"stage": 1, "exps": [{"exp": "exp-1-...", "paths": ["src/quest/render.ml"]},
                                    {"exp": "exp-2-...", "paths": ["completions/"]}]},
              {"stage": 2, "exps": [{"exp": "exp-3-...", "paths": ["src/quest/store.ml"]}]},
              ... ] }
owner approves the quest -> status flips to approved in the same approval commit.
```

## Diagram

```text
/quest framing: break down exps ─► ask grouping ─► write QUEST.md + exp_routes.json (proposed)
                                                        │ owner approval
                                                        ▼
                                          status: approved ─► Exp 1 validation reads it from branch tip
ungrouped framing ─► one exp per stage (serial, zero-cost default)
```

## Pseudocode

```python
def frame_quest(intent):
    exps = break_down(intent, acceptance="fails today")
    stages = ask_grouping(exps) or [[e] for e in exps]      # default: serial railway
    write_routes(quest, status="proposed",
                 stages=[{"stage": i + 1,
                          "exps": [{"exp": e.id, "paths": e.output_paths} for e in g]}
                         for i, g in enumerate(stages)])
```

## Tables

| Field | Value |
|---|---|
| Intent | grouping is decided at framing, by the owner, in the open — never improvised mid-run |
| Lane | standard |
| Output | grouping step + routes shape in `skills/quest/SKILL.md`; `Stage` line in the exp record shape; renders regenerated; assertions in `test/skills.sh` |
| Acceptance | cases below |
| Depends on | Exp 1 (schema it writes); Exp 2 not required — framing may precede the scheduler |

| Case | Expected after |
|---|---|
| grouped framing | `exp_routes.json` exists, stages match the owner's grouping, `paths` equal each exp record's Output paths (fixture-asserted) |
| ungrouped framing | one exp per stage; file present; behavior identical to a routes-less quest |
| owner approval | the approval commit flips `status` to `approved`; Exp 1 dispatch opens |
| exp record | carries its `Stage` line naming stage number and siblings |
| skill text | `test/skills.sh` asserts the grouping question and routes shape phrases in `skills/quest` |
| routes edited by hand later | a commit + Exp 1 revalidation; the framing fixture does not bless silent drift (`paths` vs record mismatch fails the skills fixture) |

## Acceptance test (goal block)

- **Objective:** every newly framed quest is born with
  an approvable, engine-checkable route plan.
- **Prove by:** frame a scratch quest grouped and one
  ungrouped (fixture drives the skill's file shape, not
  a live framing session); assert files, stage lines,
  and `paths` equality; `make check` green.
- **Done when:** both scratch quests carry correct
  routes, and this quest's own `exp_routes.json`
  (dogfood, below) validates under Exp 1's cases once
  Exp 1 lands.

## Prose

Context: Exp 1 makes routes checkable and Exp 2 makes
them runnable; without this exp, routes files would be
hand-written per quest — the exact prose-drift failure
the contract exists to kill. Why the default is a file
full of singletons instead of no file: uniformity — the
conductor and the owner read the same artifact for every
quest, and grouping later is an edit to a file that
already exists, not a new artifact appearing mid-quest.
Why grouping is a framing question and not a mid-run
one: mid-run grouping is scheduling by vibes; framing
grouping is a decision the owner's approval already
covers. This quest dogfoods it: its own
`exp_routes.json` (stage 1: Exp 1; stage 2: Exps 2+3 in
parallel — both depend only on Exp 1) is written at
framing as `proposed`, before Exp 1 exists to validate
it, and is the first file Exp 1's fixtures should eat.

## Tests

unit: none (skill prose + file shape) · fixtures:
grouped/ungrouped scratch framing shape, `paths`
equality, skill-text assertions in `test/skills.sh` ·
demos: this quest's own routes file, written at framing
