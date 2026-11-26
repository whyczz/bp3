---
node: skills.1
---

# skills.1 - update-skills-and-docs

TL;DR
Update `skills/{induct,induct-yolo,using-bp3,quest}/SKILL.md` (with `DEV_SKILLS` synced into `.{agents,claude,pi}/skills/` and `CORE_SKILLS` staying global per `v0.7.0`), `AGENTS.md`/`CLAUDE.md`, shell completions, and tests to reflect the 2-edge happy path (`handoff -> grade`) and `E_MISSING_ANCESTOR`.

## Acceptance gates

Design trace:

```text
$ tmp=$(mktemp -d)
$ BP3_GLOBAL_HOME="$tmp/home" BP3_COMPLETIONS_DIR="$tmp/comp" BP3_DB="$tmp/bp3.sqlite" ./bin/bp3 skills install --harness=all
$ BP3_GLOBAL_HOME="$tmp/home" ./bin/bp3 skills check
-> ok (zero drift across skills/ sources, local DEV_SKILLS, and global CORE_SKILLS)
$ cmp -s CLAUDE.md AGENTS.md
-> rc 0
$ ./test/skills.sh && ./test/completion.sh && make check-full
-> rc 0 (zero references to mandatory standalone `verify` or post-ship `land` on default plans)
```

Runnable goal block:
- **objective:** Keep every skill, doc, completion, and test synced with the v2 FSM and `E_MISSING_ANCESTOR` under `v0.7.0`'s global `CORE_SKILLS` + repo-local `DEV_SKILLS` layout.
- **prove by:** `./bin/bp3 skills check` (with isolated `BP3_GLOBAL_HOME`), `cmp -s CLAUDE.md AGENTS.md`, `./test/skills.sh`, `./test/completion.sh`, `make check-full`.
- **done when:** All checks exit `0` and no conducting skill instructs calling `--verify-verdict pass` or a redundant `land` after `grade --verdict ship` on default plans.

## Diagram

```text
skills/{induct,induct-yolo,using-bp3,quest}/SKILL.md + AGENTS.md/CLAUDE.md + completions/
  --> bp3 skills install --harness=all (with isolated BP3_GLOBAL_HOME / BP3_COMPLETIONS_DIR / BP3_DB)
  --> local DEV_SKILLS (.{agents,claude,pi}/skills/) synced; CORE_SKILLS remain source-only in repo
  --> test/skills.sh + test/completion.sh + make check-full GREEN
```

## Pseudocode

```python
def sync_skills_and_docs():
    update_skill_sources(["induct", "induct-yolo", "using-bp3", "quest"])
    sync_identical("AGENTS.md", "CLAUDE.md")
    update_completions(["completions/_bp3", "completions/bp3.bash"])
    run("BP3_GLOBAL_HOME=$tmp/home BP3_COMPLETIONS_DIR=$tmp/comp BP3_DB=$tmp/bp3.sqlite ./bin/bp3 skills install --harness=all")
    assert run("BP3_GLOBAL_HOME=$tmp/home ./bin/bp3 skills check") == 0
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) syncing all agent instructions and completions to the lean FSM. |
| Lane | micro |
| Output | Updated `skills/*/SKILL.md`, synced repo-local `DEV_SKILLS` under `.{agents,claude,pi}/skills/`, `AGENTS.md`, `CLAUDE.md`, `completions/{_bp3,bp3.bash}`, `test/{skills,completion}.sh`. |
| Acceptance | Fails today: conducting skills still instruct casting `grade --verdict ship --verify-verdict pass` followed by a separate `land` edge. |
| Depends on | `ancestry.1 - enforce-dep-commit-ancestry` |

## Prose

Per `quest/SKILL.md` step 6.6, skill edits always ride in their own node with their own verification gate. Keeping `AGENTS.md` and `CLAUDE.md` byte-identical (`cmp -s`), respecting `v0.7.0`'s global `CORE_SKILLS` vs local `DEV_SKILLS` split (never committing repo-local copies of `CORE_SKILLS`), and isolating `BP3_GLOBAL_HOME`, `BP3_COMPLETIONS_DIR`, and `BP3_DB` during test installs are mandatory repo invariants.
