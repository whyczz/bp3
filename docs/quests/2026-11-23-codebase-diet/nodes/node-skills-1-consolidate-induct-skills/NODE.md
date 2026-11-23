---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - consolidate-induct-skills: collapse dead workflow prose into 2 crisp conducting skills

## TL;DR

Remove all dead Muse JS workflow instructions (`node-loop`, `induct-grade`, `induct-land`, `induct-node`, `bind-tape`, `bp3 n`/`bp3 e` workflow claims) from `skills/` and consolidate the 4 overlapping induct skills (`induct`, `induct-yolo`, `induct-inline`, `induct-inline-yolo`) into 2 crisp skills (`induct` + `induct-yolo` running the fast inline + `agy` `/swarm` procedure, per Open question 2), updating `bin/bp3` `CORE_SKILLS`, `AGENTS.md`, `CLAUDE.md`, `test/skills.sh`, and `test/mode.sh`.

## Acceptance gates

Observed today:

```text
$ ls skills/ | grep induct
induct
induct-inline
induct-inline-yolo
induct-yolo
$ rg -n "induct-grade|node-loop|induct-node" skills/induct/SKILL.md | wc -l
# > 10 references to deleted Muse JS workflows
```

Design trace:

```text
$ rg -n "induct-grade|node-loop|induct-node|induct-land" skills/ AGENTS.md CLAUDE.md
# 0 matches
$ BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install
  - prunes retired induct-inline / induct-inline-yolo (or induct / induct-yolo per Open question 2) cleanly via GENERATED notice
  - renders all surviving skills across .pi/skills, .claude/skills, .agents/skills
$ make check-full
  - rc 0 (skills.sh, mode.sh, check-skills, check-retired-terms all green)
```

```yaml
objective: leave zero dead Muse workflow instructions in skills/ or root docs and eliminate 4-way induct skill overlap
prove by:
  - rg check returning 0 matches for deleted workflow names (node-loop, induct-grade, induct-land, induct-node) in skills/, AGENTS.md, CLAUDE.md
  - test/skills.sh, test/mode.sh, ./scripts/check-skills, ./scripts/check-retired-terms.sh
  - make check-full
done when: only the 2 crisp conducting skills remain, all renders are synced, and make check-full passes
```

## Diagram

```text
BEFORE (4 overlapping skills, 652 lines):
  skills/induct/SKILL.md (290L, dead Muse workflows)
  skills/induct-yolo/SKILL.md (152L, dead Muse workflow rails)
  skills/induct-inline/SKILL.md (139L, actual default)
  skills/induct-inline-yolo/SKILL.md (71L, actual yolo rails)

AFTER (2 crisp skills, ~210 lines):
  skills/induct/SKILL.md       (the fast inline + agy /swarm procedure)
  skills/induct-yolo/SKILL.md  (no-human rails over skills/induct/SKILL.md)
```

## Pseudocode

```python
# Follows owner's call on Open question 2 (recommended: collapse into induct + induct-yolo):
# 1. Move skills/induct-inline/SKILL.md -> skills/induct/SKILL.md (update name/frontmatter)
# 2. Move skills/induct-inline-yolo/SKILL.md -> skills/induct-yolo/SKILL.md (update name/frontmatter)
# 3. Remove skills/induct-inline/ and skills/induct-inline-yolo/
# 4. Update CORE_SKILLS in bin/bp3, cross-references in skills/using-bp3, skills/quest, AGENTS.md, CLAUDE.md
# 5. Re-render all harnesses with BP3_COMPLETIONS_DIR=<tmp> (prune_stale auto-removes old renders)
```

## Tables

| Field | Value |
|---|---|
| Intent | align the skill surface with the real engine so agents never read 442 lines of dead Muse workflow prose |
| Lane | micro |
| Output | `skills/induct/SKILL.md`, `skills/induct-yolo/SKILL.md`, deletion of `skills/induct-inline/` + `skills/induct-inline-yolo/` (or vice versa per Open question 2), `skills/using-bp3/SKILL.md`, `bin/bp3` (`CORE_SKILLS`), `AGENTS.md`, `CLAUDE.md`, rendered copies, `test/skills.sh`, `test/mode.sh` |
| Acceptance | fails today (4 induct skills + dead workflow references exist); passes when consolidated, rendered, and `make check-full` passes |
| Depends on | `retire.2 - slim-harness-to-desk` |
| Must not touch | `src/quest/*`, `CONSTRAINTS.md` |

## Prose

Rule 6.6 of `skills/quest/SKILL.md`: skill consolidation rides as its own node with its own acceptance checks. Because `bin/bp3`'s `prune_stale` keys on `<!-- GENERATED from skills/...` and `CORE_SKILLS`, removing the two redundant names from `CORE_SKILLS` automatically prunes stale renders in both self and host repos on the next `bp3 skills install`.
