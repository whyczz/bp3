---
node: skills.1
---

# skills.1 - json-quest-skills-and-completions

TL;DR
Document declarative `quest.json` authoring and `bp3 q c [<quest>] --file <path> [--scaffold]` across `skills/{quest,red-ink,using-bp3}/SKILL.md`, synced local `DEV_SKILLS`, byte-identical `AGENTS.md`/`CLAUDE.md`, and `test/{skills,completion}.sh`.

## Acceptance gates

Design trace:

```text
$ tmp=$(mktemp -d)
$ BP3_GLOBAL_HOME="$tmp/home" BP3_COMPLETIONS_DIR="$tmp/comp" BP3_DB="$tmp/bp3.sqlite" ./bin/bp3 skills install --harness=all
$ BP3_GLOBAL_HOME="$tmp/home" ./bin/bp3 skills check
-> ok
$ cmp -s CLAUDE.md AGENTS.md
-> rc 0
$ ./test/skills.sh && ./test/completion.sh && make check-full
-> rc 0
```

Runnable goal block:
- **objective:** Sync all bp3 skills, agent instructions, completions, and skill/completion tests to declarative `quest.json` authoring and `bp3 q c --file`.
- **prove by:** Isolated `bp3 skills install --harness=all` + `bp3 skills check`, `cmp -s CLAUDE.md AGENTS.md`, `./test/skills.sh`, `./test/completion.sh`, `make check-full`.
- **done when:** `make check-full` exits `0`, `quest`, `red-ink`, and `using-bp3` document `quest.json` schema v1 + `bp3 q c [<quest>] --file <path> [--scaffold]`, `AGENTS.md` and `CLAUDE.md` stay byte-identical, and `test/skills.sh` + `test/completion.sh` assert the new flags and guidance.

## Diagram

```text
skills/{quest,red-ink,using-bp3}/SKILL.md + AGENTS.md/CLAUDE.md
  --> isolated bp3 skills install --harness=all (local DEV_SKILLS synced; CORE_SKILLS global)
  --> test/skills.sh + test/completion.sh + make check-full GREEN
```

## Pseudocode

```python
def sync_json_quest_skills():
    document_quest_json_and_file_flag(["skills/quest/SKILL.md", "skills/red-ink/SKILL.md", "skills/using-bp3/SKILL.md"])
    sync_identical("AGENTS.md", "CLAUDE.md")
    run("BP3_GLOBAL_HOME=$tmp/home BP3_COMPLETIONS_DIR=$tmp/comp BP3_DB=$tmp/bp3.sqlite ./bin/bp3 skills install --harness=all")
    assert run("BP3_GLOBAL_HOME=$tmp/home ./bin/bp3 skills check") == 0
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) syncing skills, docs, and tests to declarative JSON quest init. |
| Kind | `code` |
| Lane | `micro` |
| Output | Updated `skills/{quest,red-ink,using-bp3}/SKILL.md`, local `DEV_SKILLS` renders under `.{agents,claude,pi}/skills/`, `AGENTS.md`, `CLAUDE.md`, `test/{skills,completion}.sh`. |
| Acceptance | Fails today: skills, docs, and tests do not cover `quest.json`, `bp3 q c --file`, or `--scaffold`. |
| Depends on | `init.1 - atomic-json-quest-create` |

## Prose

Per `quest/SKILL.md` step 6.6, skill updates ride as their own node with their own verification gate. Keep `AGENTS.md` and `CLAUDE.md` byte-identical (`cmp -s`), keep `CORE_SKILLS` global-only, isolate `BP3_GLOBAL_HOME`/`BP3_COMPLETIONS_DIR`/`BP3_DB` on install checks, and verify completions for `--file` and `--scaffold` in both bash and zsh traces.
