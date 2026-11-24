---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - cross-repo-drop-skills: teach /warden and using-bp3 to route cross-repo drops

## TL;DR

Update `skills/warden/SKILL.md` so host-mode `/warden` runs in downstream repos (like `predictor`) route control-plane bugs and feature requests to `bp3 drop add --to bp3` instead of mutating `~/m/bp3`, and so self-mode `/warden` / `using-bp3` check `bp3 drop list --to <repo>` for incoming items. Update `AGENTS.md`, `CLAUDE.md`, and `completions/_bp3`, re-render all harnesses via `bp3 skills install`, and verify with `test/skills.sh` and `test/completion.sh`.

## Acceptance gates

Observed today:

```text
$ grep -n "bp3 drop" skills/warden/SKILL.md skills/using-bp3/SKILL.md AGENTS.md completions/_bp3
(no matches)
```

Design trace:

```text
$ grep -n "bp3 drop" skills/warden/SKILL.md skills/using-bp3/SKILL.md AGENTS.md
  -> each file documents bp3 drop add/list/claim/done clearly and concisely
$ BP3_COMPLETIONS_DIR="$(mktemp -d)" ./bin/bp3 skills install --harness=all
  -> renders cleanly to .claude/skills, .pi/skills, .agents/skills
$ ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  -> rc 0
$ make check-full
  -> rc 0 (test/skills.sh, test/mode.sh, test/completion.sh green)
```

```yaml
objective: wire cross-repo drop workflows into bp3 skills, agent instructions, and zsh completions with synced renders
prove by:
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - test/skills.sh && test/mode.sh && test/completion.sh
  - make check-full
done when: skills, renders, AGENTS.md/CLAUDE.md, and completions all document db/repo/drop accurately and make check-full passes
```

## Diagram

```text
host repo (/warden in predictor)
   ├── app fix      ──► predictor FEEDBACK.md / local commit / predictor icebox
   └── bp3 bug/feat ──► bp3 drop add --from predictor --to bp3 --kind bug --title "..."
                                       │
                                       ▼
                           ~/.local/share/bp3/bp3.sqlite
                                       │
                                       ▼
self repo (session in bp3) ──► bp3 drop list --to bp3 ──► claim / triage / done
```

## Pseudocode

```python
def update_skills_and_docs():
    edit("skills/warden/SKILL.md", add_host_cross_repo_drop_rule=True)
    edit("skills/using-bp3/SKILL.md", add_db_repo_drop_commands=True)
    edit("AGENTS.md", add_db_repo_drop_commands=True)
    sync("CLAUDE.md", from_="AGENTS.md")
    edit("completions/_bp3", add_doors=["db", "repo", "drop"])
    run("./bin/bp3 skills install --harness=all")
    run("make check-full")
```

## Tables

| Field | Value |
|---|---|
| Intent | teach agents across repos to use `bp3 drop` / `bp3 repo` / `bp3 db` cleanly (quest skill step 6.6: skills ride as their own node) |
| Lane | standard |
| Output | `skills/warden/SKILL.md`, `skills/using-bp3/SKILL.md`, rendered `.claude`/`.pi`/`.agents` copies, `AGENTS.md`, `CLAUDE.md`, `completions/_bp3`, `test/skills.sh` |
| Acceptance | fails today (zero `bp3 drop` mentions in skills/docs/completions); passes when updated, rendered, and `make check-full` passes |
| Depends on | `drop.1 - cross-repo-drop-queue` |
| Must not touch | `src/quest/*.ml`, `CONSTRAINTS.md` |

## Prose

Keep the added prose short and high-signal (`CONTEXT.md:62`: avoid instruction bloat). `AGENTS.md` and `CLAUDE.md` stay identical in this repo; keep both in sync.

Edge cases:
- **Never edit rendered copies directly:** edit only `skills/*/SKILL.md` and regenerate via `./bin/bp3 skills install --harness=all`.
- **Host vs self mode:** `skills/warden/SKILL.md` is in `CORE_SKILLS` (installed into host repos like `predictor`), while `skills/using-bp3/SKILL.md` is in `DEV_SKILLS` (self mode). That's why putting the `bp3 drop add --to bp3` instruction in `skills/warden/SKILL.md` ensures downstream repos actually see it!
