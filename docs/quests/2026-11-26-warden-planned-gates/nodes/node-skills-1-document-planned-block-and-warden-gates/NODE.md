---
node: skills.1
slug: document-planned-block-and-warden-gates
kind: code
lane: micro
status: proposed
depends_on:
  - gate.2 - warden-planned-gate-plugs
---

# skills.1 - document-planned-block-and-warden-gates

TL;DR
Document `e block --planned --reason "..."`, `--kind human-gate`, and Warden's `planned_gates` vs `human_steer` separation in `skills/{using-bp3,warden,induct,induct-yolo}/SKILL.md` (and repo-local `using-bp3` renders), and add guard assertions in `test/skills.sh`.

## Acceptance gates

Design trace:

```text
$ grep -n -- "--planned" skills/using-bp3/SKILL.md skills/warden/SKILL.md skills/induct/SKILL.md skills/induct-yolo/SKILL.md
# matches in all 4 skills explaining when to pass --planned (declared touchpoints only) vs unplanned e block
$ make check-full
# check-skills + test/skills.sh + all 25 suites green
```

Runnable goal block:
- **objective:** Teach controller/author/warden sessions when to use `e block --planned` (declared owner touchpoints only) vs unplanned `e block` and how to interpret `planned_gates` in `bp3 warden`.
- **prove by:** `./scripts/check-skills`, `./test/skills.sh`, and `make check-full`.
- **done when:** All 4 source skills (plus `.{agents,claude,pi}/skills/using-bp3/SKILL.md` dev renders) document `--planned` and `planned_gates`, and `test/skills.sh` guards the contract.

## Diagram

```text
skills/using-bp3/SKILL.md  ---> bp3 skills install (repo-local dev renders)
skills/warden/SKILL.md     ---> bp3 skills install --global (core)
skills/induct/SKILL.md     ---> bp3 skills install --global (core)
skills/induct-yolo/SKILL.md --> bp3 skills install --global (core)
            |
            v
     test/skills.sh + make check-full
```

## Pseudocode

```python
CORE_SKILLS_TO_UPDATE = [
    "skills/warden/SKILL.md",       # explain planned_gates vs human_steer
    "skills/induct/SKILL.md",       # use e block --planned for declared owner gates
    "skills/induct-yolo/SKILL.md",  # document --planned semantics under yolo
]
DEV_SKILLS_TO_UPDATE = [
    "skills/using-bp3/SKILL.md",    # document e block [--planned] edge syntax
]
# Re-render dev skills into .{agents,claude,pi}/skills/using-bp3/SKILL.md
# and verify with ./test/skills.sh (isolated BP3_GLOBAL_HOME).
```

## Fields

| Field | Value |
|---|---|
| Intent | Sync skill guidance and tests with the new `--planned` block flag and Warden `planned_gates` output |
| Kind | `code` |
| Lane | `micro` |
| Output | Updated `skills/{using-bp3,warden,induct,induct-yolo}/SKILL.md`, repo-local `using-bp3` renders, and `test/skills.sh` assertions |
| Acceptance | Fails today (no `--planned` / `planned_gates` guidance in skills or `test/skills.sh`); passes when docs + renders + `test/skills.sh` + `make check-full` are green |
| Depends on | `gate.2 - warden-planned-gate-plugs` |

## Prose & edge cases

- **Anti-gaming guidance:** Skills must state plainly that `--planned` is ONLY for intentional owner touchpoints declared in `QUEST.md` / `NODE.md` (e.g., AV sign-off, live prod smoke holds) — never for unexpected blockers or design confusion, which must remain unplanned `e block`.
- **v0.7.0 skill layout:** Only `using-bp3` is a `DEV_SKILL` rendered repo-locally under `.{agents,claude,pi}/skills/`; `warden`, `induct`, and `induct-yolo` are `CORE_SKILLS` installed user-globally (check `test/skills.sh` `core_dirs` vs `dev_dirs`).
- **Tests:**
  - *Known cases:* `test/skills.sh` asserts `--planned` appears in `using-bp3` / `induct` / `induct-yolo` and `planned_gates` appears in `warden`.
  - *Property-based:* Omitted (static Markdown skill content and render sync verified deterministically by `check-skills` and `test/skills.sh`).
