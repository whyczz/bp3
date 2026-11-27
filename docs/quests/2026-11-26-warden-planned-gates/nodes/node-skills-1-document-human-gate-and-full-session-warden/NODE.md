---
node: skills.1
slug: document-human-gate-and-full-session-warden
kind: code
lane: micro
status: proposed
depends_on:
  - session.2 - warden-human-log-and-query-cli
---

# skills.1 - document-human-gate-and-full-session-warden

TL;DR
Update `skills/warden/SKILL.md` to integrate `bp3 warden human-log` and `bp3 warden query` for both standalone post-`/red-ink` audits (`--session latest` / proposed `<quest>`) and full-lifecycle `init..fin` quest audits, update `skills/{using-bp3,induct,induct-yolo}/SKILL.md` (+ repo-local `using-bp3` renders) to explain `--kind human-gate` vs unplanned `e block` and `planned_gates[]`, and guard in `test/skills.sh`.

## Acceptance gates

Design trace:

```text
$ grep -n "human-log\|warden query\|planned_gates" skills/warden/SKILL.md
# documents running bp3 warden human-log + query for both standalone /red-ink and full quest init..fin,
# feeding recurring human friction/preferences into <= 3 proposals without inflating findings[]
$ grep -n "human-gate" skills/using-bp3/SKILL.md skills/induct/SKILL.md skills/induct-yolo/SKILL.md
# documents modeling planned owner waits/decisions as --kind human-gate nodes so e block stays unplanned
$ make check-full
# check-skills + test/skills.sh + all suites pass
```

Runnable goal block:
- **objective:** Teach `/warden` to mine full-session human interactions (`red-ink` and `init..fin`) and teach quest authors/conductors to model planned waits as `--kind human-gate` nodes.
- **prove by:** `./scripts/check-skills`, `./test/skills.sh`, and `make check-full`.
- **done when:** All 4 source skills (plus `.{agents,claude,pi}/skills/using-bp3/SKILL.md` dev renders) pass `check-skills`, `test/skills.sh`, and `make check-full`.

## Diagram

```text
skills/warden/SKILL.md     ---> standalone /red-ink + full quest init..fin human-log & query workflow (CORE)
skills/induct/SKILL.md     ---> --kind human-gate vs unplanned e block guidance (CORE)
skills/induct-yolo/SKILL.md --> --kind human-gate vs unplanned e block guidance (CORE)
skills/using-bp3/SKILL.md  ---> --kind human-gate + warden human-log/query reference (DEV -> local renders)
            |
            v
     test/skills.sh + make check-full
```

## Pseudocode

```python
# Update skills/warden/SKILL.md:
#   - Support `/warden` standalone right after `/red-ink` (`bp3 warden human-log --session latest` or `<quest>`)
#   - Support `/warden <quest>` at landing: run `bp3 warden <quest>` (defects + planned_gates[])
#     AND `bp3 warden human-log <quest>` (init -> red-ink -> induct -> fin), using `bp3 warden query`
#     to inspect interesting turns, feeding recurring preferences/friction into <= 3 proposals
#   - Keep `findings[]` strictly deterministic (never turn learning insights into invented defects)
# Update skills/{using-bp3,induct,induct-yolo}/SKILL.md:
#   - Document modeling planned owner decisions/waits as `--kind human-gate` nodes (not `e block`)
# Re-render DEV skill `using-bp3` into .{agents,claude,pi}/skills/using-bp3/SKILL.md
```

## Fields

| Field | Value |
|---|---|
| Intent | Sync `/warden` and bp3 workflow skills with `human-gate` hygiene and full-session `human-log` / `query` |
| Kind | `code` |
| Lane | `micro` |
| Output | Updated `skills/{warden,using-bp3,induct,induct-yolo}/SKILL.md`, repo-local `using-bp3` renders, `test/skills.sh` guards |
| Acceptance | Fails today (skills don't mention `human-log`, `warden query`, `planned_gates`, or standalone `/red-ink` `/warden` audits); passes when docs + renders + `test/skills.sh` + `make check-full` pass |
| Depends on | `session.2 - warden-human-log-and-query-cli` |

## Prose & edge cases

- **v0.7.0 skill layout:** Only `using-bp3` is a `DEV_SKILL` rendered repo-locally under `.{agents,claude,pi}/skills/`; `warden`, `induct`, and `induct-yolo` are `CORE_SKILLS` installed user-globally (`test/skills.sh` checks `core_dirs` vs `dev_dirs`).
- **Keep `FEEDBACK.md` concise:** `/warden` summarizes human-involvement patterns in 1 short subsection of `FEEDBACK.md` (or standalone chat output when run right after `/red-ink` before landing) and folds the top improvements into the existing hard cap of `<= 3` proposals.
- **Tests:**
  - *Known cases:* `test/skills.sh` asserts `human-log`, `warden query`, and `planned_gates` appear in `warden/SKILL.md`, and `human-gate` guidance appears in `using-bp3`/`induct`/`induct-yolo`.
  - *Property-based:* Omitted (static Markdown skill content and render sync verified deterministically by `check-skills` and `test/skills.sh`).
