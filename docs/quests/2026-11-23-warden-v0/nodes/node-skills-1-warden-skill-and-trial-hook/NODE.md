---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - warden-skill: unified `/warden` skill replacing `/trial`

## TL;DR

Replace `skills/trial/SKILL.md` (`DEV_SKILLS`) with a single unified **`skills/warden/SKILL.md`** in **`CORE_SKILLS`** (`bin/bp3`) that wraps quest landing + self-improvement: runs the diligence gate & Landing IIUC/runnable trial, runs `bp3 warden <quest>`, writes standalone **`docs/quests/<quest>/FEEDBACK.md`**, and presents at most 3 concrete proposals (preferring deterministic lint/script/test fixes + pruning stale prose) for tiered owner disposal (small 1–2 file fixes applied cleanly on owner go; larger changes frozen to `docs/icebox/` or framed as a follow-up quest). Removes `skills/trial/` and stale rendered `trial/` copies, updates `skills/quest/SKILL.md` and `skills/induct/SKILL.md`, and re-renders all harnesses.

## Acceptance gates

Observed today:

```text
$ ls skills/warden/SKILL.md
ls: skills/warden/SKILL.md: No such file or directory
$ ls skills/trial/SKILL.md
skills/trial/SKILL.md
```

Design trace:

```text
/warden <quest> (or /warden for repo sweep)
  1. Landing gate (when landing a quest): diligence gate + Landing IIUC + runnable trial/demo.
  2. Deterministic audit: runs `bp3 warden <quest>` (never invents findings outside deterministic output + cited evidence).
  3. Inspects cited ledger/git/transcript refs and groups findings by root cause.
  4. Writes standalone `docs/quests/<quest>/FEEDBACK.md` (human post-land notes + Warden summary + <=3 proposals + owner disposition).
  5. Proposes <= 3 concrete improvements ranked by ROI:
       - prefers lint / script / test fixes over prose
       - includes a pruning check when proposing prose edits
       - tiered disposal on owner approval: small 1–2 file harness fixes applied directly as a clean commit; big multi-file fixes frozen to `docs/icebox/` or framed as a follow-up quest
  6. Stops for owner disposal ("warden proposes, owner disposes"; never auto-commits or pushes alone).
```

```yaml
objective: unify quest landing and self-improvement into one /warden CORE_SKILLS skill writing FEEDBACK.md with <=3 tiered proposals and cleanly retire /trial
prove by:
  - test/skills.sh: skills/warden/SKILL.md exists and rendered across all harnesses; skills/trial/ and rendered trial/ directories removed; asserts FEEDBACK.md, <=3 proposal cap, deterministic-first + pruning rule, tiered disposal, and owner-disposes rule; skills/quest and skills/induct point to warden
  - test/mode.sh: warden listed in CORE_SKILLS and trial removed from DEV_SKILLS in bin/bp3
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - make check-full
done when: skills.sh, mode.sh, check-skills, and make check-full pass with zero stale renders or leftover trial dirs
```

## Diagram

```text
/warden <quest> (at goal_fin, replacing /trial)
   ├── 1. diligence gate + Landing IIUC + runnable trial
   ├── 2. bp3 warden <quest> (deterministic 12-plug audit)
   ├── 3. inspect cited evidence (diffs, ledgers, transcripts)
   ├── 4. write docs/quests/<quest>/FEEDBACK.md
   └── 5. present <= 3 proposals (lint/script > prose + prune check)
            └── owner disposes: small 1–2 file commit | docs/icebox/ | follow-up quest | skip
```

## Pseudocode

```python
def warden_skill(quest=None):
    if quest:
        run_diligence_and_landing_iiuc(quest)
    report = bp3_json(f"warden {quest}" if quest else "warden")
    proposals = draft_top_proposals(report["findings"], limit=3, prefer="lint_or_script", prune_check=True)
    if quest:
        write_feedback_md(quest, report, proposals)
    return present_for_owner_disposal(report, proposals)  # tiered: small commit vs icebox/quest
```

## Tables

| Field | Value |
|---|---|
| Intent | unify `/trial` and `/warden` into one bounded, owner-gated landing + self-improvement skill |
| Lane | micro |
| Output | `skills/warden/SKILL.md` (new), delete `skills/trial/` + stale `.{pi,claude,agents}/skills/trial/`, `skills/quest/SKILL.md`, `skills/induct/SKILL.md`, `bin/bp3` (`CORE_SKILLS` + `DEV_SKILLS`), rendered `.pi/skills/`, `.claude/skills/`, `.agents/skills/`, `test/skills.sh`, `test/mode.sh` |
| Acceptance | fails today (`skills/warden/SKILL.md` absent, `trial` still in `DEV_SKILLS`); passes when `skills.sh`, `mode.sh`, `check-skills`, and `make check-full` pass |
| Depends on | `cli.1 - warden-door` |
| Must not touch | `src/*`, `CONSTRAINTS.md` |

## Prose

- Rule 6.6 of `skills/quest/SKILL.md`: skill authoring/renaming rides as its own dedicated node.
- Settled in red-ink closing red chair: `trial` was previously in `DEV_SKILLS` (`bin/bp3:37`); `warden` moves to `CORE_SKILLS` so host repos get `/warden` too, and `skills/quest/SKILL.md:170,273` + `skills/induct/SKILL.md:27` + `test/skills.sh:94` are updated in the same commit.
- Always run `./bin/bp3 skills install --harness=all` with `BP3_COMPLETIONS_DIR="$(mktemp -d)"` so global zsh completions are never touched.
- **Test split:** Known semantic invariant assertions in `test/skills.sh` and `test/mode.sh`; property-based tests omitted (stated decision: Markdown skill).
