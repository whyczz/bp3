---
date: 2026-11-25
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - planning-worktree-guards: guard `icebox`, `quest`, `red-ink`, `RELEASING.md`, and `AGENTS.md`/`CLAUDE.md`

## TL;DR

Wire the clean-runway draft-desk guard into `skills/icebox/SKILL.md`, `skills/quest/SKILL.md`, and `skills/red-ink/SKILL.md`, update `RELEASING.md` to document Tiered CAS `merge-tree` promotion (`--ff-only`, `E_MERGE_CONFLICT`, `E_VERIFY_FAILED`), add the always-loaded "Clean runway" rule and draft-desk commands to `AGENTS.md` and `CLAUDE.md` (kept byte-identical), re-render `.agents/skills/`, `.claude/skills/`, and `.pi/skills/` via `bp3 skills install --harness=all` (with `BP3_DB` and `BP3_COMPLETIONS_DIR` isolated), and lock every invariant in `test/skills.sh`.

## Acceptance gates

Observed today (2026-11-25, `e60eb8a`):

```text
$ grep -n -- '--draft\|target_dirty' skills/icebox/SKILL.md skills/quest/SKILL.md skills/red-ink/SKILL.md AGENTS.md CLAUDE.md || echo "0 matches"
0 matches
$ grep -n 'creates no' skills/icebox/SKILL.md
68:- Instructions only: this skill writes docs. It creates no
69:  branches, ledger lines, or Board records.
$ grep -n 'merge-tree\|--ff-only' RELEASING.md || echo "0 matches"
0 matches
```

Design trace:

```text
# Every planning skill references the deterministic draft-desk guard:
$ grep -l 'bp3 harness desk prepare --draft' skills/icebox/SKILL.md skills/quest/SKILL.md skills/red-ink/SKILL.md
skills/icebox/SKILL.md
skills/quest/SKILL.md
skills/red-ink/SKILL.md

# icebox documents the clean-master immediate-commit bypass (target_dirty == false) + draft fallback:
$ grep -n 'target_dirty' skills/icebox/SKILL.md
...

# RELEASING.md documents Tiered CAS merge-tree promotion + --ff-only:
$ grep -n 'merge-tree\|--ff-only' RELEASING.md
...

# AGENTS.md and CLAUDE.md stay byte-identical and carry the Clean runway rule + draft desk commands:
$ cmp -s AGENTS.md CLAUDE.md && grep -n 'prepare --draft' AGENTS.md CLAUDE.md
# rc 0

# All rendered harness skill copies match source:
$ ./bin/bp3 skills check
{"ok":true,...}
$ ./test/skills.sh && make check-full
# rc 0
```

```yaml
objective: add the clean-runway draft-desk guard to skills/{icebox,quest,red-ink}/SKILL.md and AGENTS.md/CLAUDE.md, update RELEASING.md for Tiered CAS merge-tree releases, re-render all harness skill copies, and lock the invariants in test/skills.sh
prove by:
  - ./bin/bp3 skills check -> {"ok":true,...}
  - cmp -s AGENTS.md CLAUDE.md -> rc 0
  - ./test/skills.sh (with new assertions covering icebox target_dirty bypass + draft fallback, quest/red-ink draft-desk guard, rendered copies across .agents/.claude/.pi, RELEASING.md CAS merge-tree docs, and AGENTS.md/CLAUDE.md parity)
  - make check && make check-full
done when: all skill, render, lint, and full-suite gates pass cleanly with zero stray writes to real ~/.local/share/bp3/bp3.sqlite or ~/.zsh/completions
```

## Diagram

```text
Planning session starts (/icebox, /quest, /red-ink)
  │
  ├── already in a non-master worktree (quest/* or draft/*)?
  │     └── proceed directly in current worktree
  │
  └── on master / main?
        ├── /icebox (single-turn):
        │     call `bp3 harness desk list` -> read `.target_dirty`
        │       ├── target_dirty == false
        │       │     └── write docs/icebox/YYYY-MM-DD-<slug>.md + commit immediately on master
        │       │         (0s dirty window; parallel quests merge cleanly via release.1 CAS!)
        │       └── target_dirty == true
        │             └── `bp3 harness desk prepare --draft icebox-<slug>`
        │                 write + commit in draft desk
        │                 `bp3 harness desk land --draft icebox-<slug>` (once master is clean)
        │
        └── /quest or /red-ink (multi-turn):
              always `bp3 harness desk prepare --draft quest-<slug>` (or `red-ink-<slug>`)
              author / iterate / adopt in draft desk (master stays 100% clean)
              on owner approval: commit + `bp3 harness desk land --draft <slug>`
                (lands immediately via 50ms CAS rebase loop; master stays fresh!)
```

## Pseudocode

```python
# Shared pre-flight guard across icebox, quest, red-ink:
def ensure_clean_runway(kind: Literal["icebox", "quest", "red-ink"], slug: str):
    branch = git("branch", "--show-current")
    if branch not in ("master", "main"):
        return current_dir()  # already isolated in a quest/* or draft/* worktree

    if kind == "icebox":
        status = json.loads(run("bp3 harness desk list"))
        if not status["target_dirty"]:
            return current_dir()  # write + commit immediately in same turn (0s dirty window)

    draft_slug = f"{kind}-{slug}"
    res = json.loads(run(f"bp3 harness desk prepare --draft {draft_slug}"))
    return res["path"]

# Closeout for draft desk:
def finish_draft(draft_slug: str):
    # commit cleanly inside draft desk first
    res = run_json(f"bp3 harness desk land --draft {draft_slug}")
    if res["ok"]:
        return "landed onto master via CAS rebase and draft desk released"
    # only fails if master is dirty (E_DIRTY_TREE) or real merge conflict (E_MERGE_CONFLICT)
    return f"kept cleanly on draft/{draft_slug}; resolve {res['error']['code']} and retry"
```

## Tables

| Field | Value |
|---|---|
| Intent | wire clean-runway draft-desk guard into `icebox`, `quest`, `red-ink`, update `RELEASING.md` and `AGENTS.md`/`CLAUDE.md`, re-render harness skills, and lock in `test/skills.sh` |
| Lane | standard |
| Output | `skills/icebox/SKILL.md`, `skills/quest/SKILL.md`, `skills/red-ink/SKILL.md`, `.agents/skills/{icebox,quest,red-ink}/SKILL.md`, `.claude/skills/{icebox,quest,red-ink}/SKILL.md`, `.pi/skills/{icebox,quest,red-ink}/SKILL.md`, `RELEASING.md`, `AGENTS.md`, `CLAUDE.md`, `test/skills.sh` |
| Acceptance | fails today (0 `--draft` / `target_dirty` references in skills or `AGENTS.md`/`CLAUDE.md`; `RELEASING.md` still states strict FF only); passes when guards, renders, docs, and `test/skills.sh` + `make check-full` pass |
| Depends on | `draft.1 - draft-desk-cli`, `release.1 - cas-merge-release` |
| Must not touch | `src/*`, `CONSTRAINTS.md`, `completions/*`, `.gitignore` |

## Prose

Why the `/icebox` bypass checks `target_dirty == false` (and does NOT need to wait for active quests): once `release.1` lands, an icebox commit on `master` is classified as `Doc_only` drift — parallel quests automatically merge over it via `git merge-tree --write-tree` in milliseconds without manual rebasing or re-grading. So single-turn `/icebox` stays zero-ceremony whenever `master` is clean, and falls back to a `draft/icebox-<slug>` desk only if `master` is dirty.

Why multi-turn `/quest` and `/red-ink` still **always** use a `draft/<slug>` desk when invoked on `master`/`main`: multi-turn design and review sessions keep files modified across many minutes or hours (and create `*.red-ink.md` working copies), which would leave `master` dirty and trip `E_DIRTY_TREE` on parallel promotions. Using a `draft/` desk keeps `master` clean throughout the whole session and lands immediately via `land --draft` on approval.

When running `./bin/bp3 skills install --harness=all` during authoring, always isolate both `BP3_DB` and `BP3_COMPLETIONS_DIR` (e.g., `BP3_DB=/tmp/bp3-render.sqlite BP3_COMPLETIONS_DIR=/tmp/bp3-comp ./bin/bp3 skills install --harness=all`) and remove temp files afterward.

## Tests

- **Known cases (`test/skills.sh`):**
  - Assert `skills/icebox/SKILL.md` (and rendered `.agents`/`.claude`/`.pi` copies) references `target_dirty`, `bp3 harness desk prepare --draft`, and `bp3 harness desk land --draft`, and no longer contains `"It creates no branches"`.
  - Assert `skills/quest/SKILL.md` and `skills/red-ink/SKILL.md` (and all rendered copies) reference `bp3 harness desk prepare --draft` and `bp3 harness desk land --draft`.
  - Assert `RELEASING.md` documents `merge-tree` CAS promotion and `--ff-only`.
  - Assert `AGENTS.md` and `CLAUDE.md` are byte-identical and reference `prepare --draft` / `land --draft`.
  - Assert `./bin/bp3 skills check` passes (`ok: true`) and `./scripts/check-skills` passes in `make lint`.
- **Property-based:** omitted — skill markdown content and exact render synchronization are deterministic string/file-equality checks; no input domain benefits from randomized generation.
