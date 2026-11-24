---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - release-skills: update /quest, /warden, and /using-bp3 skills and re-render all harnesses

## TL;DR

Dedicated skill-change node (per `skills/quest/SKILL.md` step 6.6): update `skills/quest/SKILL.md` (`bump: major | minor | patch | none` in file shape + `RELEASING.md` check), `skills/warden/SKILL.md` (run `bp3 release <quest> --dry-run` in Landing IIUC to preview the release tag & "What changed" notes, and promote via `BP3_DECIDER=human bp3 release <quest>` on owner go), and `skills/using-bp3/SKILL.md` (document `bp3 release <quest>`, `bp3 release --commit <sha>`, and tag-gated local auto-sync). Re-render all harness copies via `./bin/bp3 skills install --harness=all` and add skill assertions in `test/skills.sh`.

## Acceptance gates

Observed today (2026-11-23):

```text
$ grep -n 'bump:' skills/quest/SKILL.md
# (no output)
$ grep -n 'bp3 release' skills/warden/SKILL.md skills/using-bp3/SKILL.md
# (no output)
```

Design trace (after `skills.1` lands):

```text
$ grep -n 'bump:' skills/quest/SKILL.md
# matches frontmatter bump: major | minor | patch | none + RELEASING.md reference
$ grep -n 'bp3 release' skills/warden/SKILL.md skills/using-bp3/SKILL.md
# matches bp3 release <quest> (--dry-run in /warden, BP3_DECIDER=human owner gate) and bp3 release --commit <sha>
$ ./bin/bp3 skills install --harness=all
# renders all skills cleanly across .pi/skills, .claude/skills, .agents/skills
$ ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
# ok
$ ./test/skills.sh && ./test/mode.sh
# ok (including new assertions for bump: and bp3 release)
$ make check-full
# exit 0
```

```yaml
objective: update quest, warden, and using-bp3 source skills for bump:, bp3 release (<quest> and --commit <sha>), and tag-gated auto-sync, re-render all harnesses, and pin assertions in test/skills.sh
prove by:
  - ./bin/bp3 skills install --harness=all
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - ./test/skills.sh && ./test/mode.sh
  - make check-full
done when: all three source skills and every rendered copy reflect bump: and bp3 release, test/skills.sh asserts them, and make check-full exits 0
```

## Diagram

```text
skills/quest/SKILL.md     ──► frontmatter adds bump: major|minor|patch|none (per RELEASING.md)
skills/warden/SKILL.md    ──► Landing IIUC runs bp3 release <q> --dry-run; owner go runs BP3_DECIDER=human bp3 release <q>
skills/using-bp3/SKILL.md ──► documents bp3 release <quest>, bp3 release --commit <sha>, and tag-gated auto-sync
         │
         ▼
./bin/bp3 skills install --harness=all ──► .pi/skills, .claude/skills, .agents/skills
         │
         ▼
./test/skills.sh + ./test/mode.sh + make check-full
```

## Pseudocode

```python
# Source edits only in skills/<name>/SKILL.md (never hand-edit rendered copies):
# 1. skills/quest/SKILL.md:
#    - Add `bump: major | minor | patch | none` to the File shape frontmatter block
#    - Reference RELEASING.md and scripts/check-bump in step 5
# 2. skills/warden/SKILL.md:
#    - In step 1 (Landing IIUC), preview release with `bp3 release <quest> --dry-run`
#    - In step 5 (owner disposal), on owner promote approval run `BP3_DECIDER=human bp3 release <quest>`
# 3. skills/using-bp3/SKILL.md:
#    - Document `bp3 release <quest>` (human-gated promotion + release) and `bp3 release --commit <sha>` (patch bugfix release)
#    - Note tag-gated local auto-sync (`BP3_NO_AUTO_SYNC=1` kill-switch)
# 4. Run `./bin/bp3 skills install --harness=all`
# 5. Add assertions in `test/skills.sh` verifying source + renders carry bump: and bp3 release
```

## Tables

| Field | Value |
|---|---|
| Intent | Sync agent instructions across all harnesses with `bump:`, `bp3 release`, and tag-gated local auto-sync |
| Lane | micro |
| Output | `skills/quest/SKILL.md`, `skills/warden/SKILL.md`, `skills/using-bp3/SKILL.md`, rendered copies under `.pi/skills/`, `.claude/skills/`, `.agents/skills/`, and `test/skills.sh` |
| Acceptance | `scripts/check-skills`, `test/skills.sh`, `test/mode.sh`, and `make check-full` pass |
| Depends on | `cli.1 - release-door`, `lint.1 - bump-lint-and-docs`, `sync.1 - tag-gated-local-sync` |

| Skill | Change |
|---|---|
| `skills/quest/SKILL.md` | Add `bump: major \| minor \| patch \| none` to File shape frontmatter; reference `RELEASING.md` |
| `skills/warden/SKILL.md` | Preview release via `bp3 release <quest> --dry-run` in Landing IIUC; run `BP3_DECIDER=human bp3 release <quest>` only on explicit owner promotion go |
| `skills/using-bp3/SKILL.md` | Document `bp3 release <quest>`, `bp3 release --commit <sha>`, `--dry-run`, `--no-gh`, `--no-install`, `--publish-only`, and tag-gated auto-sync |

## Prose

Per `skills/quest/SKILL.md` step 6.6, skill changes always ride in their own node with render and test verification rather than being folded into code nodes. Keep edits surgical and concise (`CONTEXT.md:62`: no prose bloat).

## Tests

- `test/skills.sh`: assert `skills/quest/SKILL.md` carries `bump:` in File shape, `skills/warden/SKILL.md` references `bp3 release <quest>`, and `skills/using-bp3/SKILL.md` documents `bp3 release` + `--commit` + `BP3_DECIDER=human`; verify rendered copies across `.pi/skills`, `.claude/skills`, and `.agents/skills` stay in sync after `bp3 skills install --harness=all`.
- `test/mode.sh` + `scripts/check-skills`: pass cleanly.
