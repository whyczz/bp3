---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: active
---

# skills.1 - consolidate-induct-skills: promote `induct-inline` -> `induct` and `induct-inline-yolo` -> `induct-yolo`

## TL;DR

Promote `docs/icebox/2026-11-23-induct-inline-becomes-induct.md`: replace the dead Muse workflow `skills/induct/SKILL.md` and `skills/induct-yolo/SKILL.md` with `skills/induct-inline/SKILL.md` -> `skills/induct/SKILL.md` and `skills/induct-inline-yolo/SKILL.md` -> `skills/induct-yolo/SKILL.md`, delete `skills/induct-inline/` and `skills/induct-inline-yolo/`, update `bin/bp3` (`CORE_SKILLS`), `skills/{using-bp3,quest,warden}/SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `scripts/check-retired-terms.sh`, `test/skills.sh`, and `test/mode.sh`, and re-render all harness trees (`.agents/skills/`, `.claude/skills/`, `.pi/skills/`), pruning stale `induct-inline*` renders cleanly.

## Acceptance gates

Observed today (2026-11-24):

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
$ ls skills/ | grep induct
induct
induct-yolo
$ rg -n "induct-grade|node-loop|induct-node|induct-land|induct-inline" skills/ AGENTS.md CLAUDE.md
# 0 matches
$ BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=all
  - prunes retired induct-inline and induct-inline-yolo renders cleanly via GENERATED notice
  - renders all surviving skills across .pi/skills, .claude/skills, .agents/skills
$ make check && make check-full
  - rc 0 (skills.sh, mode.sh, check-skills, check-retired-terms all green)
```

```yaml
objective: promote induct-inline -> induct and induct-inline-yolo -> induct-yolo, remove all dead Muse workflow prose, and sync every render and doc
prove by:
  - ls skills/ shows only induct and induct-yolo (no induct-inline*)
  - rg check returning 0 matches for deleted workflow names and induct-inline in skills/, AGENTS.md, CLAUDE.md
  - test/skills.sh (including pruning stale induct-inline* renders + updated .pi/settings.json list), test/mode.sh, ./scripts/check-skills, ./scripts/check-retired-terms.sh
  - make check && make check-full
done when: only 2 crisp conducting skills remain, all renders are synced, stale induct-inline* renders prune automatically, and make check-full passes
```

## Diagram

```text
BEFORE (4 overlapping skills):
  skills/induct/SKILL.md             (dead Muse workflows)
  skills/induct-yolo/SKILL.md        (dead Muse workflow rails)
  skills/induct-inline/SKILL.md      (actual default)
  skills/induct-inline-yolo/SKILL.md (actual yolo rails)

AFTER (2 crisp skills):
  skills/induct/SKILL.md             (promoted from induct-inline: inline + agy /swarm)
  skills/induct-yolo/SKILL.md        (promoted from induct-inline-yolo: no-human rails over induct)
```

## Pseudocode

```python
# 1. Move skills/induct-inline/SKILL.md -> skills/induct/SKILL.md (name: induct, drop induct-vs-induct-inline table & dead workflow refs)
# 2. Move skills/induct-inline-yolo/SKILL.md -> skills/induct-yolo/SKILL.md (name: induct-yolo, reference induct skill)
# 3. Delete skills/induct-inline/ and skills/induct-inline-yolo/
# 4. Update CORE_SKILLS in bin/bp3 (remove induct-inline, induct-inline-yolo)
# 5. Update cross-references in skills/{using-bp3,quest,warden}/SKILL.md, AGENTS.md, CLAUDE.md, scripts/check-retired-terms.sh
# 6. Re-render all harnesses: BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=all (prune_stale auto-removes old induct-inline* renders)
# 7. Update test/skills.sh (lines 119, 265-414 + add pruning test for stale induct-inline* renders) and test/mode.sh
```

## Tables

| Field | Value |
|---|---|
| Intent | align the skill surface with the real engine so `/induct` and `/induct-yolo` are the default and zero dead workflow prose remains |
| Lane | micro |
| Output | `skills/{induct,induct-yolo,using-bp3,quest,warden}/SKILL.md`, deletion of `skills/induct-inline*`, `bin/bp3` (`CORE_SKILLS`), `AGENTS.md`, `CLAUDE.md`, `scripts/check-retired-terms.sh`, rendered `.{agents,claude,pi}/skills/`, `test/skills.sh`, `test/mode.sh` |
| Acceptance | fails today (4 induct skills + dead workflow references exist); passes when consolidated, rendered, and `make check-full` passes |
| Depends on | `retire.2 - slim-harness-to-desk` |
| Must not touch | `src/quest/*`, `CONSTRAINTS.md` |

## Prose

Rule 6.6 of `skills/quest/SKILL.md`: skill consolidation rides as its own node with its own acceptance checks. Because `bin/bp3`'s `prune_stale` keys on `<!-- GENERATED from skills/...` and `CORE_SKILLS`, removing `induct-inline` and `induct-inline-yolo` from `CORE_SKILLS` automatically prunes stale renders in both self and host repos on the next `bp3 skills install`. Also clean `AGENTS.md` / `CLAUDE.md` Commands tables to drop the retired `bp3 n` / `bp3 e` lines.

## Tests

- **Known cases:** `ls skills/` grep (`induct` + `induct-yolo` only), 0-match `rg` over `skills/`, `AGENTS.md`, `CLAUDE.md`, `test/skills.sh` (verifying updated `.pi/settings.json`, semantic invariants on `induct` / `induct-yolo`, and `prune_stale` removing legacy `induct-inline*` renders), `test/mode.sh`, `./scripts/check-skills`, `./scripts/check-retired-terms.sh`, and `make check && make check-full`.
- **Property-based:** omitted — prose and render consolidation verified by exact golden/drift checks.
