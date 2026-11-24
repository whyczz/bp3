---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - docs-and-skills-cutover: update AGENTS/CLAUDE, skills, warden backup hook, and completions

## TL;DR

Update `AGENTS.md`, `CLAUDE.md`, `skills/using-bp3/SKILL.md`, `skills/warden/SKILL.md` (add `bp3 db backup` step at quest landing when `backup_dir` is configured), and `completions/_bp3` to reflect that quest state, ledgers, metrics, config, and desks now live in `~/.local/share/bp3/bp3.sqlite` (not `refs/heads/bp3/*` or `state.yaml`), re-render all harnesses via `bp3 skills install --harness=all`, and verify with `make check-full`.

## Acceptance gates

Observed today:

```text
$ grep -n "state.yaml" AGENTS.md skills/using-bp3/SKILL.md
AGENTS.md:10:Never hand-edit generated quest state. `state.yaml` and
AGENTS.md:30:  state.yaml             GENERATED: stage, commit, cycle (a cache)
```

Design trace:

```text
$ grep -n "bp3 db backup" skills/warden/SKILL.md AGENTS.md completions/_bp3
  -> documented cleanly in all three
$ BP3_COMPLETIONS_DIR="$(mktemp -d)" ./bin/bp3 skills install --harness=all
  -> all harness renders synced cleanly
$ ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  -> rc 0
$ make check-full
  -> rc 0
```

```yaml
objective: update all docs, skills, renders, and shell completions to match SQLite-backed quest storage and wire bp3 db backup into /warden landing
prove by:
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - test/skills.sh && test/mode.sh && test/completion.sh
  - make check-full
done when: zero stale refs/heads/bp3 or state.yaml instructions remain in live docs/skills, renders are synced, and make check-full passes
```

## Diagram

```text
AGENTS.md (synced == CLAUDE.md)   ──► "The one rule": never hand-edit bp3.sqlite; use bp3 q / bp3 db
skills/using-bp3/SKILL.md         ──► bp3 q, bp3 db info|check|backup|import-refs|export-quest
skills/warden/SKILL.md            ──► at goal_fin landing: run bp3 db backup (if backup_dir configured)
completions/_bp3                  ──► add db subcommands (info, check, backup, import-refs, export-quest)
       │
       ▼
bp3 skills install --harness=all  ──► .claude/skills, .pi/skills, .agents/skills
```

## Pseudocode

```python
def cutover_docs_and_skills():
    update_agents_and_claude_md()
    update_skill("skills/using-bp3/SKILL.md")
    update_skill("skills/warden/SKILL.md", add_backup_at_landing=True)
    update_completions("completions/_bp3")
    run("./bin/bp3 skills install --harness=all")
    run("make check-full")
```

## Tables

| Field | Value |
|---|---|
| Intent | align all agent instructions, skills, and completions with SQLite storage and add the `/warden` backup hook (quest skill step 6.6) |
| Lane | standard |
| Output | `AGENTS.md`, `CLAUDE.md`, `skills/using-bp3/SKILL.md`, `skills/warden/SKILL.md`, rendered copies under `.claude`/`.pi`/`.agents`, `completions/_bp3` |
| Acceptance | fails today (`AGENTS.md` still describes `state.yaml` / `ledger.jsonl` on git refs; zero `bp3 db backup` in `skills/warden/SKILL.md`); passes when updated, rendered, and `make check-full` passes |
| Depends on | `tests.1 - migrate-fixture-suites` |
| Must not touch | `src/quest/*.ml`, `CONSTRAINTS.md` |

## Prose

Keep `AGENTS.md` concise (~100 lines, `CONTEXT.md:60`) — replacing the old `state.yaml`/`ledger.jsonl` layout bullets with `~/.local/share/bp3/bp3.sqlite` should actually *shrink* `AGENTS.md`. Never edit rendered copies in `.claude/`, `.pi/`, or `.agents/` directly; always regenerate with `./bin/bp3 skills install --harness=all`.

Edge cases:
- **No `backup_dir` configured during `/warden`:** `/warden` should check `bp3 config` / `bp3 db info` first (or handle `E_BACKUP_CONFIG` gracefully as a one-line tip to configure `backup_dir`), never failing quest landing if the user hasn't set a backup folder yet.
- **Historical quest docs (`docs/quests/2026-11-*/`):** Do NOT edit landed historical quest files or `CONTEXT.md` historical lessons; only live instructions (`AGENTS.md`, `CLAUDE.md`, `skills/`, `completions/`).
