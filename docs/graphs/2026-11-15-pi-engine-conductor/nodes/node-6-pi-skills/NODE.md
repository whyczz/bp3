---
date: 2026-11-15
goal: ../GRAPH.md
exp: 6
status: proposed
---

# Exp 6 — pi-skills: the skill changes ride as their own exp

## TL;DR

Rule 6.6: skill changes are never folded into a code
exp. Everything the pi engine teaches the skills —
induct's pi engine notes, role prompt files as skill
assets, `.pi` render/install assertions, the dispatcher's
install path (`bp3 skills install` → `.pi/extensions/`,
if Exp 2 settles it there) — lands in this exp with
skills tests as its gate.

## Diagram

```text
skills/induct/SKILL.md        (+ pi engine section)
skills/pi-engine/roles/*.md   (author, reviewer, checker, lander)
extensions/bp3-pi/          (the package; installed like a skill asset)
        |  bp3 skills install --harness=all
        v
.pi/extensions/  .agents/  .claude/   (renders asserted)
```

| Field | Value |
|---|---|
| Intent | children on every harness read the same pi procedure |
| Lane | standard (skill change; own exp per rule 6.6) |
| Output | skill edits + role files + install wiring + `test/skills.sh` assertions |
| Depends on | Exp 2 (install path), Exp 3 (procedure text) |

## Acceptance (fails today: no pi content in any skill)

| Case | Expected |
|---|---|
| renders | `bp3 skills install --harness=all` places the pi roles + dispatcher where pi loads them; check-skills green |
| one procedure | induct's pi section names the same dispatch table as Exp 2; grep asserts the state→step rows match |
| tests | skills tests count grows by the new assertions and passes; no harness render drifts (cmp on installed copies) |

## Acceptance test (goal block)

- **Objective:** the pi engine is installed, not
  hand-copied.
- **Prove by:** `make check` (skills suite) + a fresh
  `pi` session in a scratch repo listing the roles.
- **Done when:** skills tests green and the scratch
  session sees the pi engine assets.

## Tests

known cases: Acceptance table · property-based: none ·
fixtures: skills.sh scratch-root install · demos: the
scratch session listing, observed.

## Context

The muse round taught this twice: installed copies
drift silently, and a skill edited mid-exp contaminates
the exp's grade. Hence: all skill text waits for this
exp, and this exp's only code is install wiring.
