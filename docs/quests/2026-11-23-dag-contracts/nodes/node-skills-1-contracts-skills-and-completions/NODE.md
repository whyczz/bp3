---
node: skills.1
---

# skills.1 - contracts-skills-and-completions

TL;DR
Update `skills/{quest,induct,induct-yolo,using-bp3}/SKILL.md` (with `DEV_SKILLS` synced into `.{agents,claude,pi}/skills/` and `CORE_SKILLS` staying global per `v0.7.0`), `AGENTS.md`/`CLAUDE.md`, shell completions, and skill/completion tests to document the 5 node flavors (`code | direct | research | explore | human-gate`), `E_PROTECTED_FILE`, `e iterate`, and `approve`.

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
-> rc 0
```

Runnable goal block:
- **objective:** Wire the 5 node flavors (`code | direct | research | explore | human-gate`), `E_PROTECTED_FILE`, and `Explore` bounds into all bp3 skills, docs, and shell completions under `v0.7.0`'s global `CORE_SKILLS` + repo-local `DEV_SKILLS` layout.
- **prove by:** `./bin/bp3 skills check` (with isolated `BP3_GLOBAL_HOME`), `cmp -s CLAUDE.md AGENTS.md`, `./test/skills.sh`, `./test/completion.sh`, `make check-full`.
- **done when:** `make check-full` exits `0`, `quest` and `induct` skills document when to use `research`, `explore`, `human-gate`, `direct`, and `code`, and completions cover `--kind`, `approve`, `iterate`, `--target`, `--max-iterations`, `--budget-min`, `--outcome`, and `--allow-protected`.

## Diagram

```text
skills/{quest,induct,induct-yolo,using-bp3}/SKILL.md + AGENTS.md/CLAUDE.md + completions/
  --> bp3 skills install --harness=all (with isolated BP3_GLOBAL_HOME / BP3_COMPLETIONS_DIR / BP3_DB)
  --> local DEV_SKILLS (.{agents,claude,pi}/skills/) synced; CORE_SKILLS remain source-only in repo
  --> test/skills.sh + test/completion.sh + make check-full GREEN
```

## Pseudocode

```python
def sync_contracts_skills():
    update_quest_skill_with_five_node_kinds()
    update_induct_skills_with_research_explore_and_human_gate()
    sync_identical("AGENTS.md", "CLAUDE.md")
    update_completions(["completions/_bp3", "completions/bp3.bash"])
    run("BP3_GLOBAL_HOME=$tmp/home BP3_COMPLETIONS_DIR=$tmp/comp BP3_DB=$tmp/bp3.sqlite ./bin/bp3 skills install --harness=all")
    assert run("BP3_GLOBAL_HOME=$tmp/home ./bin/bp3 skills check") == 0
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) syncing all agent instructions and completions to the 5 node flavors and `E_PROTECTED_FILE`. |
| Lane | micro |
| Output | Updated `skills/*/SKILL.md`, synced repo-local `DEV_SKILLS` under `.{agents,claude,pi}/skills/`, `AGENTS.md`, `CLAUDE.md`, `completions/{_bp3,bp3.bash}`, `test/{skills,completion}.sh`. |
| Acceptance | Fails today: skills and completions lack `--kind code|direct|research|explore|human-gate`, `approve`, `iterate`, `--target`, `--max-iterations`, `--budget-min`, `--outcome`, and `--allow-protected`. |
| Depends on | `research.1 - research-and-explore-nodes` |

## Prose

Per `quest/SKILL.md` step 6.6, skill edits always ride as their own node with their own test gate. Keep `AGENTS.md` and `CLAUDE.md` byte-identical (`cmp -s`), respect `v0.7.0`'s global `CORE_SKILLS` vs local `DEV_SKILLS` split (never committing repo-local copies of `CORE_SKILLS`), isolate `BP3_GLOBAL_HOME`/`BP3_COMPLETIONS_DIR`/`BP3_DB` during test installs, and verify `completions/_bp3` and `completions/bp3.bash` complete the new flags and edges.
