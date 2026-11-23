---
date: 2026-11-22
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - downstream-skills: desks in both modes, bump at framing, warnings in reports (skill node)

## TL;DR

The skill text catches up with the code. induct, induct-inline and
using-bp3 stop saying host mode has no desk: both modes prepare a quest
desk and author only there, grade desks work the same, and the one
difference left is the read (`./bin/bp3` in self mode, `bp3` on PATH in
host mode). The quest skill's file shape gains `bump:`. Promotion
(`goal_fin`) follows `RELEASING.md`. Conductors quote `W_INSTALL_BEHIND`
and `W_VERSION_AHEAD` in their reports, so the warnings reach the owner.

## Acceptance gates

Observed today:

```text
$ grep -n 'has no desk\|self mode only\|host mode works in the repo' skills/induct/SKILL.md skills/induct-inline/SKILL.md
skills/induct/SKILL.md:76:   tracked: bp3 is a tool) has no desk, installs core skills only,
skills/induct/SKILL.md:91:2.5. Quest worktree, by default (self mode only; host mode
skills/induct-inline/SKILL.md:35:   author only there; host mode works in the repo. One session
$ grep -n 'bump' skills/quest/SKILL.md                # nothing
$ grep -rn 'W_INSTALL_BEHIND\|RELEASING.md' skills/  # nothing
```

Design trace:

```text
$ ./test/skills.sh
  induct (source and renders): step 2.5 prepares a desk in both modes; host desks default to ../<repo>.desks/<run_id>;
    host reads call bp3 on PATH, self reads ./bin/bp3 from the desk; "has no desk" and "self mode only" absent;
    goal_fin names RELEASING.md's promotion steps; the induct report quotes W_INSTALL_BEHIND and W_VERSION_AHEAD
  induct-inline: step 1 prepares the quest desk in both modes; "host mode works in the repo" absent; its report quotes them too
  induct-inline-yolo, induct-yolo: the check-in report lists any version warning seen
  quest: the file shape's frontmatter carries bump: major | minor | patch | none, decided against RELEASING.md
  using-bp3: one line naming desks in both modes
$ ./bin/bp3 skills check            # fresh renders
```

```yaml
objective: a session in a downstream repo follows the skills into a desk, frames quests with a bump, and reports version warnings to the owner
prove by:
  - add-bp3-skill gates for each edited skill (overlap, stateless, trigger checks), recorded in the build notes
  - test/skills.sh new assertions on the source and every render
  - make check-full
done when: the assertions pass, each new one fails on master's text, and the removed phrases are absent
```

## Diagram

```text
quest         frontmatter: bump: minor  ───────────────────────────────► promotion (RELEASING.md)
induct(-inline) prepare the quest desk
   self ─► ./bin/bp3 harness desk prepare --quest q ─► .bp3/worktrees/quest-q   reads: ./bin/bp3
   host ─►   bp3     harness desk prepare --quest q ─► ../<repo>.desks/quest-q  reads: bp3 on PATH
grade desks: the same prepare with --run grade-<node>-c<cycle>-a<attempt> --commit <sha>, in both modes
verdict warnings (W_INSTALL_BEHIND, W_VERSION_AHEAD) ─► the induct report / check-in report ─► owner
```

## Pseudocode

```python
def prepare_quest_desk(quest, mode):
    bp3 = "./bin/bp3" if mode == "self" else "bp3"
    return run(bp3, "harness", "desk", "prepare", "--quest", quest)["path"]   # author only there

def report(...):
    seen = {w for v in verdicts_this_run for w in v.warnings if w in ("W_INSTALL_BEHIND", "W_VERSION_AHEAD")}
    if seen: say(f"bp3 version: {', '.join(sorted(seen))} (run make install in the bp3 checkout; the owner's call)")
```

## Tables

| Field | Value |
|---|---|
| Intent | the induct-inline default runs downstream as written, and versions are decided and reported |
| Lane | micro (skill node) |
| Output | `skills/induct/SKILL.md`, `skills/induct-inline/SKILL.md`, `skills/induct-yolo/SKILL.md`, `skills/induct-inline-yolo/SKILL.md`, `skills/quest/SKILL.md`, `skills/using-bp3/SKILL.md`, renders, `test/skills.sh` |
| Acceptance | the assertions above; fail today |
| Depends on | desk.1 (the host path), version.1 (`bump:`, `RELEASING.md`), install.3 (`W_INSTALL_BEHIND`) |

| Skill | Today | After |
|---|---|---|
| induct, step 2.5 | self mode only; host children work in the repo root | both modes; host reads via PATH |
| induct, mode paragraph | host "has no desk" | host desk beside the repo |
| induct, `goal_fin` | owner gate | owner gate, steps per `RELEASING.md` |
| induct-inline, step 1 | host mode works in the repo | both modes prepare the quest desk |
| induct, induct-inline reports; yolo check-in reports | silent on versions | quote `W_INSTALL_BEHIND`, `W_VERSION_AHEAD` |
| quest, file shape | `status`, `home_repo`, `date` | plus `bump:` |
| using-bp3 | silent | one line: desks in both modes |

## Prose

The "no desk in host mode" rule came from dogfood.3, whose concern was
the read strategy (`$DESK/bin/bp3` vs `bp3` on PATH), not isolation.
The code never enforced it: `harness desk prepare` ran in a host clone
and both checkouts read the same state. With desk.1 the host desk also
builds, so the rule has no reason left.

`bump:` belongs to framing because that's where design gets argued
(version.1). The quest skill only names the field and points at
`RELEASING.md`; it doesn't copy the table, so the two can't drift.

Quoting warnings in reports is the last hop of install.3's propagation:
a verdict's `warnings` reaches the conductor; the report reaches the
owner. Reinstalling stays the owner's call (it changes the installation),
so the report says what to run and doesn't run it.

One skill node for this quest's skill text, per quest step 6.6: skills
are how sessions behave, so they get their own gate, separate from code.

## Tests

Known cases: the skills.sh patterns above, each absent from master's
text, plus the removed phrases' absence and `bp3 skills check` fresh.
Property-based: omitted; skill text has no generator.
