---
date: 2026-11-25
quest: ../../QUEST.md
node: skills.1
status: active
---

# skills.1 - document-auto-cleanup-and-prune: update `using-bp3` and `warden` skills for automatic release cleanup and `desk prune`

## TL;DR

Document automatic post-release desk/branch cleanup (`bp3 release`) and the new `bp3 harness desk prune [--dry-run]` GC command concisely in `skills/using-bp3/SKILL.md` and `skills/warden/SKILL.md`, re-render `.{agents,claude,pi}/skills/`, and lock with assertions in `test/skills.sh`.

## Acceptance gates

Observed today (2026-11-25, `2ca58e09`):

```text
$ rg -n "desk prune" skills/
# 0 matches
```

Design trace:

```text
$ rg -n "desk prune" skills/ .agents/skills/ .claude/skills/ .pi/skills/
# matches in using-bp3/SKILL.md (and warden/SKILL.md) across source + all 3 rendered trees
$ BP3_COMPLETIONS_DIR=/tmp/c ./bin/bp3 skills check
{"ok":true,"fresh":[],"skills_checked":...}
$ ./test/skills.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: document automatic post-release desk/branch cleanup and bp3 harness desk prune in using-bp3 and warden skills and keep all renders fresh
prove by:
  - skills/using-bp3/SKILL.md and skills/warden/SKILL.md mention automatic desk/branch cleanup on bp3 release and bp3 harness desk prune [--dry-run]
  - ./bin/bp3 skills check returns ok:true and ./scripts/check-skills passes
  - test/skills.sh asserts presence across skills/ and all 3 rendered trees, and make check-full passes (25/25 suites)
done when: skills and renders are synced, test/skills.sh guards the documentation, and all 25 suites pass
```

## Diagram

```text
skills/using-bp3/SKILL.md (+ warden/SKILL.md)
  ──► BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=all
  ──► .{agents,claude,pi}/skills/{using-bp3,warden}/SKILL.md
  ──► ./bin/bp3 skills check + ./test/skills.sh
```

## Pseudocode

```python
# 1. Update skills/using-bp3/SKILL.md item 9 (bp3 release) to note automatic clean-desk + merged-branch cleanup
#    and add one concise line for `bp3 harness desk prune [--dry-run]`.
# 2. Update skills/warden/SKILL.md step 5 (Promote / release) to note release auto-releases clean quest desks.
# 3. Re-render all harnesses with isolated BP3_COMPLETIONS_DIR and BP3_DB.
# 4. Add assertion loop in test/skills.sh covering skills/ and all 3 rendered dirs.
```

## Tables

| Field | Value |
|---|---|
| Intent | ensure agents and humans know `bp3 release` cleans up after itself and `bp3 harness desk prune` sweeps leftovers |
| Lane | micro |
| Output | `skills/using-bp3/SKILL.md`, `skills/warden/SKILL.md`, rendered `.{agents,claude,pi}/skills/{using-bp3,warden}/SKILL.md`, `test/skills.sh` |
| Acceptance | fails today (`desk prune` absent from `skills/`); passes when updated, re-rendered, guarded in `test/skills.sh`, and `make check-full` passes |
| Depends on | `clean.1 - release-auto-cleanup`, `clean.2 - desk-prune-verb` |
| Must not touch | `src/*`, `bin/bp3`, `Makefile`, `CONSTRAINTS.md` |

## Prose

Per Rule 6.6 of `skills/quest/SKILL.md`, skill prose updates ride in their own node with their own render and freshness assertions. Keep edits to 1–2 concise lines per file (zero bloat).

## Tests

- **Known cases (`test/skills.sh`):** assert `desk prune` and post-release cleanup wording appear in `skills/` and `.{agents,claude,pi}/skills/` for `using-bp3` and `warden`, plus `./bin/bp3 skills check` and `make check-full`.
