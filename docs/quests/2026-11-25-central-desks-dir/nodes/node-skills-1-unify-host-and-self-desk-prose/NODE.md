---
date: 2026-11-25
quest: ../../QUEST.md
node: skills.1
status: active
---

# skills.1 - unify-host-and-self-desk-prose: drop `"host mode works in the repo"` split from `skills/induct/SKILL.md`

## TL;DR

Update `skills/induct/SKILL.md` to drop the obsolete `"In self mode, prepare the quest desk ... and author only there; host mode works in the repo"` branch so both self and host repos prepare and author in their central quest desk (`bp3 harness desk prepare --quest <quest>`), re-render all harness copies (`.agents/skills/`, `.claude/skills/`, `.pi/skills/`), and add a regression check in `test/skills.sh`.

## Acceptance gates

Observed today (2026-11-25, `c8bfbb9`):

```text
$ grep -n "host mode works in the repo" skills/induct/SKILL.md
23:   and author only there; host mode works in the repo. One session
```

Design trace:

```text
$ grep -rn "host mode works in the repo" skills/ .agents/skills/ .claude/skills/ .pi/skills/
# 0 matches
$ BP3_COMPLETIONS_DIR=/tmp/c ./bin/bp3 skills check
{"ok":true,"fresh":[],"skills_checked":...}
$ ./test/skills.sh && ./test/mode.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: align skills/induct/SKILL.md and all harness renders with unified central desks for both self and host repos
prove by:
  - grep -rn "host mode works in the repo" skills/ .agents/skills/ .claude/skills/ .pi/skills/ returns 0 matches
  - skills/induct/SKILL.md instructs preparing the quest desk (`bp3 harness desk prepare --quest <quest>`) unconditionally (no self-only gate)
  - ./bin/bp3 skills check returns ok:true and ./scripts/check-skills passes
  - test/skills.sh (with assertion forbidding "host mode works in the repo" in induct), test/mode.sh, and make check-full pass (25/25 suites)
done when: source skill and all harness renders are synced, test/skills.sh guards against the old self/host desk split, and make check-full passes
```

## Diagram

```text
BEFORE (skills/induct/SKILL.md:21-23):
  "In self mode, prepare the quest desk (...) and author only there;
   host mode works in the repo."

AFTER (skills/induct/SKILL.md + .agents/.claude/.pi renders):
  "Prepare the quest desk (`bp3 harness desk prepare --quest <quest>`)
   and author only there (desks live centrally under `~/.bp3/desks/`
   in both self and host modes)."
```

## Pseudocode

```python
# 1. Edit skills/induct/SKILL.md lines 21-23 to unify self & host desk instruction (keep concise, zero bloat).
# 2. Check skills/induct-yolo/SKILL.md, skills/using-bp3/SKILL.md, skills/warden/SKILL.md for any remaining
#    ".bp3/worktrees" or "host mode works in the repo" references (fix if any).
# 3. Re-render all harnesses: BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=all
# 4. Add regression assertion in test/skills.sh ensuring induct does not restrict desks to self mode.
```

## Tables

| Field | Value |
|---|---|
| Intent | ensure host repos (like `~/m/predictor`) automatically use isolated central quest desks under `/induct` instead of authoring directly on the user's main branch |
| Lane | micro |
| Output | `skills/induct/SKILL.md`, rendered `.{agents,claude,pi}/skills/induct/SKILL.md`, `test/skills.sh` |
| Acceptance | fails today (`"host mode works in the repo"` present in `skills/induct/SKILL.md:23`); passes when updated, re-rendered, guarded in `test/skills.sh`, and `make check-full` passes |
| Depends on | `desks.1 - central-layout-and-worktree` |
| Must not touch | `src/*`, `Makefile`, `bin/bp3`, `CONSTRAINTS.md` |

## Prose

Rule 6.6 of `skills/quest/SKILL.md`: skill changes ride as their own node with their own acceptance checks. Keeping `skills/induct/SKILL.md` concise (replacing 1 sentence with 1 sentence, net 0 bloat) honors the pruning discipline while making central desks active everywhere as soon as `v0.6.0` auto-syncs to host repos.

## Tests

- **Known cases (`test/skills.sh`, `test/mode.sh`):** negative grep ensuring `"host mode works in the repo"` is absent from `skills/induct/SKILL.md` and its renders, positive grep for `bp3 harness desk prepare --quest`, `bp3 skills check`, `./scripts/check-skills`, `./scripts/check-retired-terms.sh`, and `make check-full`.
- **Property-based:** omitted — prose and render freshness verified by deterministic checks.
