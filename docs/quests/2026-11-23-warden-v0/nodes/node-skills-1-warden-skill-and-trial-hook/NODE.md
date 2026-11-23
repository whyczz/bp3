---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - warden-skill-and-trial-hook: `/warden` skill and `/trial` `goal_fin` integration

## TL;DR

Author `skills/warden/SKILL.md` (added to `CORE_SKILLS` in `bin/bp3`), wire a Warden pass into `skills/trial/SKILL.md` right before `goal_fin` promotion, and re-render all harnesses. `/warden` runs `bp3 q <quest> warden`, inspects cited evidence, and outputs at most 3 concrete, owner-approved patch proposals (preferring deterministic lint/script/test fixes and pruning stale rules over appending prose).

## Acceptance gates

Observed today:

```text
$ ls skills/warden/SKILL.md
ls: skills/warden/SKILL.md: No such file or directory
$ rg -n "warden" skills/trial/SKILL.md || echo "none"
none
```

Design trace:

```text
/warden <quest> (or /warden --all-landed)
  1. Runs `bp3 q <quest> warden` (never invents findings outside deterministic output + cited evidence).
  2. Groups findings by root cause and inspects cited diffs/ledgers/scripts.
  3. Proposes <= 3 concrete patches ranked by time/token ROI:
       - prefers lint / script / test fixes over prose
       - includes a pruning check: if proposing a prose line in GRADING.md / AGENTS.md / a skill,
         names a stale line to delete or explains why none can be cut
  4. Stops and hands proposals to the owner ("warden proposes, owner disposes"; never edits state or pushes alone).

/trial <quest>
  - Runs the Warden pass as part of landing review and includes the summary in the Landing IIUC.
```

```yaml
objective: close the human-in-the-loop self-improvement workflow with /warden and wire it into /trial without prompt bloat
prove by:
  - test/skills.sh: skills/warden/SKILL.md exists, rendered to all harnesses, asserts <=3 proposal cap, deterministic-first + pruning rule, and owner-disposes rule; skills/trial/SKILL.md references warden
  - test/mode.sh: warden listed in CORE_SKILLS in bin/bp3
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - make check-full
done when: skills.sh, mode.sh, check-skills, and make check-full pass with zero stale renders
```

## Diagram

```text
/trial <quest> (at goal_fin) ──► invokes /warden <quest>
                                        │
                                        ├─ 1. bp3 q <quest> warden (deterministic findings)
                                        ├─ 2. inspect cited evidence (diffs, ledgers, metrics)
                                        ├─ 3. draft <= 3 concrete patches (lint/script > prose + prune check)
                                        └─ 4. present to owner -> owner picks 0..3 -> land or icebox
```

## Pseudocode

```python
def warden_skill(quest=None, all_landed=False):
    report = bp3_json(f"q warden --all-landed" if all_landed else f"q {quest} warden")
    if report["counts"]["total"] == 0:
        return "Warden clean: 0 findings."
    groups = group_by_root_cause(report["findings"])
    proposals = []
    for g in top_roi(groups, limit=3):
        inspect_evidence(g.evidence_refs)
        proposals.append(draft_patch(g, prefer="lint_or_script", include_prune_check=True))
    return present_for_owner_disposal(report, proposals)  # never auto-apply
```

## Tables

| Field | Value |
|---|---|
| Intent | give every landed quest a fast, bounded, owner-gated self-improvement pass |
| Lane | micro |
| Output | `skills/warden/SKILL.md` (new), `skills/trial/SKILL.md`, `bin/bp3` (`CORE_SKILLS`), rendered `.pi/skills/`, `.claude/skills/`, `.agents/skills/`, `test/skills.sh`, `test/mode.sh` |
| Acceptance | fails today (`skills/warden/SKILL.md` absent, `trial` doesn't call warden); passes when `skills.sh`, `mode.sh`, `check-skills`, and `make check-full` pass |
| Depends on | `cli.1 - warden-door` |
| Must not touch | `src/quest/*`, `CONSTRAINTS.md` |

## Prose

Rule 6.6 of `skills/quest/SKILL.md`: skill authoring is its own dedicated node.

Why the `<= 3 proposals` + pruning check matters (`CONTEXT.md:59, 62`): every automated "self-improving agent" fails the same way if unchecked — it appends defensive prose after every run until instructions bloat into unread noise. Putting a hard cap of 3 proposals, ranking deterministic lint/script fixes above prose, and requiring a prune check keeps `AGENTS.md`, `GRADING.md`, and skills lean over dozens of quests.
