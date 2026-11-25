---
date: 2026-11-25
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - global-activation-prose-and-bp3-migration: global skill guards, `bp3/backpack.toml`, untrack 21 local `CORE_SKILLS` copies

## TL;DR

Complete the migration in `bp3` itself and update skill/repo docs: add a crisp 1-line `backpack.toml` activation guard to all 7 `CORE_SKILLS` (`induct`, `induct-yolo`, `quest`, `icebox`, `naming`, `red-ink`, `warden`) so global skills stay dormant in non-bp3 repos; document `backpack.toml`, `bp3 init-repo`, `bp3 skills prune-local`, and `missing_repo_config` in `skills/warden/SKILL.md` and `skills/using-bp3/SKILL.md`; commit `bp3`'s own <=15-line `backpack.toml`; remove the 21 duplicated repo-local `CORE_SKILLS` renders and legacy repo-local hook files (`.claude/hooks.json`, `.muse/hooks.json`, `.agents/hooks.json`, bp3 entries in `.claude/settings.json`), keeping ONLY the 3 `DEV_SKILLS` (`add-bp3-skill`, `add-yap-skill`, `using-bp3`) rendered locally; and update `AGENTS.md`, `CLAUDE.md`, `RELEASING.md`, and `test/skills.sh` repo-checkout assertions.

## Acceptance gates

Observed today (`2026-11-25`, `a7087eb`):

```text
$ test -f backpack.toml && echo exists || echo missing
missing
$ ls .agents/skills/ | wc -l
      10
$ grep -l 'backpack\.toml' skills/*/SKILL.md || echo "none"
none
$ test -f .agents/hooks.json && echo exists
exists
```

Design trace:

```text
$ wc -l < backpack.toml   # <= 15
11
$ cat backpack.toml
version = 1
repo = "bp3"

[grade]
gate = "make check-full"

[warden]
grade_wall_s = 300

[release]
target = "master"

$ for d in .agents/skills .claude/skills .pi/skills; do ls "$d"; done
# each prints ONLY: add-bp3-skill, add-yap-skill, using-bp3 (3 each, 0 CORE_SKILLS)
$ test ! -e .claude/hooks.json && test ! -e .muse/hooks.json && test ! -e .agents/hooks.json
$ grep -l 'backpack\.toml' skills/{induct,induct-yolo,quest,icebox,naming,red-ink,warden}/SKILL.md | wc -l
7
$ ./bin/bp3 config | jq '.ok, .repo_config.repo, (.warnings // []) | length'
true
"bp3"
0
$ ./bin/bp3 warden --no-sessions | jq 'all(.findings[]; .rule != "missing_repo_config")'
true
$ ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
skills check: ok (19 files)
$ make check-full   # 25/25 suites green
```

```yaml
objective: add backpack.toml activation guard to all 7 CORE_SKILLS, document backpack.toml/prune-local in warden and using-bp3, commit bp3/backpack.toml, prune bp3's 21 local CORE_SKILLS copies and legacy repo-local hooks, and sync AGENTS.md/CLAUDE.md/RELEASING.md
prove by:
  - cat backpack.toml (<= 15 lines, parses cleanly via ./bin/bp3 config with 0 warnings)
  - ls .agents/skills/ .claude/skills/ .pi/skills/ (strictly add-bp3-skill, add-yap-skill, using-bp3 in each; 0 CORE_SKILLS)
  - test ! -e .claude/hooks.json && test ! -e .muse/hooks.json && test ! -e .agents/hooks.json
  - grep -l 'backpack.toml' skills/{induct,induct-yolo,quest,icebox,naming,red-ink,warden}/SKILL.md (7 matches)
  - BP3_GLOBAL_HOME="$work/home" ./bin/bp3 skills install --harness=all && BP3_GLOBAL_HOME="$work/home" ./bin/bp3 skills check (ok: true)
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills (19 files ok)
  - make check && make check-full (25/25 suites green)
done when: bp3 itself runs fully on committed backpack.toml + global CORE_SKILLS + 3 local DEV_SKILLS, docs match reality, and make check-full is 100% green
```

## Diagram

```text
Before (in bp3 repo):
  skills/ (10 sources)
  .{agents,claude,pi}/skills/ (30 generated copies: 21 CORE + 9 DEV)
  .{agents,claude,muse}/hooks.json + .claude/settings.json (4 repo-local hook files)
  (no backpack.toml)

After (in bp3 repo):
  backpack.toml  (11 lines: version=1, repo="bp3", [grade], [warden], [release])
  skills/ (10 sources: 7 CORE with backpack.toml activation guard + 3 DEV)
  .{agents,claude,pi}/skills/ (9 generated copies: ONLY 3 DEV_SKILLS each)
  (0 repo-local hook files; global hooks + 7 CORE_SKILLS live in ~/)
```

## Pseudocode

```python
# 1. Add activation guard line to each of the 7 CORE_SKILLS in skills/<s >/SKILL.md:
#    "Scope: active in git repos with `backpack.toml` at root (or when explicitly
#     invoked to bootstrap via `bp3 init-repo`); stay dormant in non-bp3 repos."
# 2. Update skills/warden/SKILL.md and skills/using-bp3/SKILL.md with:
#    - backpack.toml manifest + missing_repo_config finding
#    - bp3 init-repo + bp3 skills prune-local migration
# 3. Write backpack.toml at bp3 repo root (<= 15 lines).
# 4. Run BP3_GLOBAL_HOME=<tmp> ./bin/bp3 skills install --harness=all
#    and ./bin/bp3 skills prune-local (removes 21 local CORE_SKILLS + legacy hooks,
#    keeps 3 DEV_SKILLS in .{agents,claude,pi}/skills/ + updates .pi/settings.json).
# 5. Update AGENTS.md, CLAUDE.md (keep identical!), RELEASING.md (section 5:
#    global skills/hooks auto-installed on release; retire auto-commit sync prose).
# 6. Update test/skills.sh lines 17-21 to assert DEV_SKILLS exclusions in $repo/.pi/settings.json
#    and assert 0 CORE_SKILLS in $repo/.{agents,claude,pi}/skills/.
```

## Tables

| Field | Value |
|---|---|
| Intent | update skill prose for global activation, commit `bp3/backpack.toml`, and migrate `bp3` off local `CORE_SKILLS` and legacy repo-local hooks |
| Lane | standard |
| Output | `backpack.toml`, `skills/*/SKILL.md`, `.{agents,claude,pi}/skills/` (3 `DEV_SKILLS` kept, 21 `CORE_SKILLS` deleted), `.pi/settings.json`, removal of `.{agents,claude,muse}/hooks.json` & `.claude/settings.json`, `AGENTS.md`, `CLAUDE.md`, `RELEASING.md`, `test/skills.sh` |
| Acceptance | fails today (`backpack.toml` missing, 10 skills in `.agents/skills/`, legacy `.agents/hooks.json` present, 0 `CORE_SKILLS` mention `backpack.toml`); passes when `bp3` is migrated and `make check-full` is green |
| Depends on | `manifest.2 - wire-manifest-consumers-and-warnings`, `global.1 - global-skills-and-hooks-installer`, `global.2 - hooks-backpack-gate-and-retire-autosync` |
| Must not touch | `src/*`, `bin/bp3`, `scripts/*`, `CONSTRAINTS.md`, `Makefile` |

## Prose

Keep `AGENTS.md` and `CLAUDE.md` byte-for-byte identical (existing repo convention).

Check `test/cleanliness.sh` and `test/skills.sh`: make sure removing `.claude/hooks.json`, `.claude/settings.json`, `.muse/hooks.json`, and `.agents/hooks.json` leaves zero dangling references or empty tracked dirs, and that `scripts/check-skills skills .pi/skills .agents/skills .claude/skills` passes cleanly over the 10 source skills + 3×3=9 `DEV_SKILLS` (= 19 files).

Note that during `induct` grading, `./bin/bp3 skills check` should be verified with an isolated `BP3_GLOBAL_HOME` so grading never depends on or mutates the machine's live `~/` until the owner runs `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-global-skills-and-backpack-toml`.

## Tests

- **Skill lint (`./scripts/check-skills`):** validates YAML frontmatter and name/description across `skills/` (10) + `.{agents,claude,pi}/skills/` (3×3 = 9) = 19 files.
- **Fixture (`test/skills.sh`):** asserts `$repo` itself tracks `backpack.toml`, tracks ONLY `DEV_SKILLS` in `.{agents,claude,pi}/skills/` (0 `CORE_SKILLS`), and keeps matching `DEV_SKILLS` exclusions in `.pi/settings.json`.
- **Full gate (`make check-full`):** all 25/25 suites green.
