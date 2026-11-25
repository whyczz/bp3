---
date: 2026-11-25
quest: ../../QUEST.md
node: global.1
status: proposed
---

# global.1 - global-skills-and-hooks-installer: user-global `CORE_SKILLS` + non-clobbering hooks + `prune-local`

## TL;DR

Refactor `bin/bp3` (`skills install`, `skills check`, `skills prune-local`) and `scripts/install-bp3.sh` so the 7 `CORE_SKILLS` and `bp3` hooks install **user-globally** under `$BP3_GLOBAL_HOME` / `$HOME` (`~/.gemini/config/skills/`, `~/.claude/skills/`, `~/.pi/agent/skills/`, `~/.codex/skills/`, `~/.muse/skills/`; hooks merged non-destructively into `~/.claude/settings.json`, `~/.gemini/config/hooks.json`, `~/.muse/hooks.json`), while the 3 `DEV_SKILLS` (`add-bp3-skill`, `add-yap-skill`, `using-bp3`) render strictly repo-locally inside `bp3` (`self` mode). Host repos receive **zero** generated skill or hook files on `bp3 init` / `bp3 skills install`; `bp3 skills prune-local` cleanly strips legacy generated bp3 copies and hooks from existing repos without touching repo-owned skills or custom user hooks.

## Acceptance gates

Observed today (`2026-11-25`, `a7087eb`):

```text
$ grep -n 'harness_target' -A 9 bin/bp3
83:harness_target() {
84:  case "$1" in
85:    pi)     echo ".pi/skills" ;;
86:    claude) echo ".claude/skills" ;;
87:    codex)  echo ".agents/skills" ;;
88:    muse)   echo ".agents/skills" ;;
89:    agy)    echo ".agents/skills" ;;
90:    *) return 1 ;;
91:  esac
92:}
$ ./bin/bp3 skills prune-local 2>&1 | head -1
usage: bp3 init [--harness=<pi|claude|codex|muse|agy|all>] | ...
```

Design trace:

```text
$ export BP3_GLOBAL_HOME="$work/home" BP3_COMPLETIONS_DIR="$work/comp" BP3_DB="$work/bp3.sqlite"

$ # 1. Host mode install: global CORE_SKILLS + global hooks; ZERO files written in host repo!
$ BP3_TARGET="$work/host" ./bin/bp3 skills install --harness=all
mode: host (...)
installed 7 CORE_SKILLS -> $work/home/.{gemini/config,claude,pi/agent,codex,muse}/skills/...
installed global hooks -> $work/home/.claude/settings.json, $work/home/.gemini/config/hooks.json, $work/home/.muse/hooks.json
$ test ! -e "$work/host/.agents" && test ! -e "$work/host/.claude" && test ! -e "$work/host/.pi"  # rc 0
$ # Custom user hooks in ~/.claude/settings.json & ~/.gemini/config/hooks.json preserved verbatim!

$ # 2. Self mode install: global CORE_SKILLS + global hooks + ONLY 3 DEV_SKILLS local in bp3
$ BP3_TARGET="$work/self" ./bin/bp3 skills install --harness=all
$ ls "$work/self/.agents/skills/"
add-bp3-skill
add-yap-skill
using-bp3

$ # 3. bp3 skills prune-local in legacy host repo: removes generated bp3 copies, keeps repo-owned skills!
$ BP3_TARGET="$work/legacy_host" ./bin/bp3 skills prune-local
$ test ! -e "$work/legacy_host/.agents/skills/quest"
$ test -f "$work/legacy_host/.agents/skills/new-strategy/SKILL.md"  # preserved!
$ test ! -e "$work/legacy_host/.claude/hooks.json"

$ # 4. scripts/install-bp3.sh installs bp3-q + bp3 + share/bp3/skills AND global skills/hooks
$ PREFIX="$work/prefix" BP3_GLOBAL_HOME="$work/home2" ./scripts/install-bp3.sh "$art"
$ test -f "$work/home2/.gemini/config/skills/warden/SKILL.md"
$ test -f "$work/home2/.claude/skills/warden/SKILL.md"
$ test -f "$work/home2/.pi/agent/skills/warden/SKILL.md"

$ ./test/skills.sh && ./test/mode.sh && ./test/install.sh && make check-full  # rc 0
```

```yaml
objective: install CORE_SKILLS (7) and non-clobbering bp3 hooks user-globally in bin/bp3 and scripts/install-bp3.sh, keep DEV_SKILLS (3) self-local, add bp3 skills prune-local, and update bp3 skills check
prove by:
  - test/skills.sh (isolated with BP3_GLOBAL_HOME="$work/home"): global CORE_SKILLS render & freshness check, non-clobbering hook merge into ~/.claude/settings.json and ~/.gemini/config/hooks.json with planted custom hooks, stale-skill pruning never touching yap/hand-written skills, self-mode DEV_SKILLS local render + local CORE_SKILLS pruning, bp3 skills prune-local preserving repo-owned skills and non-bp3 hooks
  - test/mode.sh (isolated with BP3_GLOBAL_HOME="$work/home"): host install writes 0 files in host repo while populating global CORE_SKILLS + hooks; self install writes only DEV_SKILLS locally + CORE_SKILLS globally
  - test/install.sh (isolated with BP3_GLOBAL_HOME="$work/home"): scripts/install-bp3.sh updates global skills and global hooks in lockstep with bp3-q, and BP3_SKIP_GLOBAL_SKILLS=1 opts out cleanly
  - shellcheck bin/bp3 scripts/install-bp3.sh && make check && make check-full
done when: all tests pass with zero writes to real $HOME during tests, host repos receive zero generated files, and custom user hooks/skills are never clobbered
```

## Diagram

```text
bin/bp3 skills install --harness=all  (also invoked by scripts/install-bp3.sh)
  │
  ├── ALWAYS -> User-global ($BP3_GLOBAL_HOME or $HOME):
  │     ├── CORE_SKILLS (7: induct, induct-yolo, quest, icebox, naming, red-ink, warden)
  │     │     ├── .gemini/config/skills/<s >/SKILL.md   (agy)
  │     │     ├── .claude/skills/<s>/SKILL.md           (claude)
  │     │     ├── .pi/agent/skills/<s>/SKILL.md         (pi)
  │     │     ├── .codex/skills/<s>/SKILL.md            (codex)
  │     │     └── .muse/skills/<s>/SKILL.md             (muse)
  │     └── Non-clobbering global hooks (cmd: "bp3 q hooks || true"):
  │           ├── .claude/settings.json   (upsert only bp3 q hooks entries per event)
  │           ├── .gemini/config/hooks.json (upsert only top-level "bp3" key)
  │           └── .muse/hooks.json        (muse)
  │
  ├── IF mode == self -> Repo-local ($target):
  │     ├── DEV_SKILLS (3: add-bp3-skill, add-yap-skill, using-bp3) -> .{agents,claude,pi}/skills/
  │     ├── prune any local GENERATED CORE_SKILLS copies from .{agents,claude,pi}/skills/
  │     └── .pi/settings.json exclusions for DEV_SKILLS only
  │
  └── IF mode == host -> ZERO files written into $target (auto-registers in bp3.sqlite only)

bin/bp3 skills prune-local (migration helper for existing repos):
  └── scans $target/.{agents,claude,pi}/skills/*/SKILL.md for "<!-- GENERATED from skills/"
      -> deletes ONLY generated bp3 copies (+ legacy .claude/hooks.json, .agents/hooks.json, .muse/hooks.json,
         bp3 entries in .claude/settings.json, bp3 exclusions in .pi/settings.json)
      -> NEVER touches hand-written repo skills or non-bp3 hooks
```

## Pseudocode

```python
# bin/bp3
def global_home() -> str:
    return env("BP3_GLOBAL_HOME") or env("HOME")

def global_skill_dir(harness: str) -> str:
    return {
        "agy":    ".gemini/config/skills",
        "claude": ".claude/skills",
        "pi":     ".pi/agent/skills",
        "codex":  ".codex/skills",
        "muse":   ".muse/skills",
    }[harness]

def merge_claude_global_hooks(settings_path: str, hook_cmd: str):
    # Read existing JSON (default {}), validate object
    # For each event in [SessionStart, PreToolUse, PostToolUse, PostToolUseFailure,
    #                    SubagentStart, SubagentStop, Stop, SessionEnd]:
    #   keep all entries whose nested hooks[].command does NOT contain "bp3 q hooks"
    #   append {"hooks": [{"type": "command", "command": hook_cmd}]}
    # Atomic write via tmp + mv

def merge_agy_global_hooks(hooks_path: str, hook_cmd: str):
    # Read existing JSON (default {}), validate object
    # Set .bp3 = { SessionStart, PreToolUse (run_command), PostToolUse (run_command), Stop }
    # Preserve all other top-level named hook groups! Atomic write via tmp + mv

def skills_prune_local(target: str):
    # In host mode: prune all GENERATED skills; in self mode: prune GENERATED skills not in DEV_SKILLS
    # Remove empty skill dirs only if empty
    # Remove .claude/hooks.json, .muse/hooks.json, .agents/hooks.json ONLY if they contain "bp3 q hooks"
    # Strip "bp3 q hooks" entries from $target/.claude/settings.json (delete file only if empty {})
    # Strip pruned skill exclusions from $target/.pi/settings.json
    # Emit JSON summary {"ok": true, "pruned_skills": [...], "pruned_hooks": [...]}
```

## Tables

| Field | Value |
|---|---|
| Intent | move `CORE_SKILLS` and `bp3` hooks to user-global harness locations, keep `DEV_SKILLS` self-local, wire `install-bp3.sh`, and ship `bp3 skills prune-local` |
| Lane | high-blast-radius |
| Output | `bin/bp3`, `scripts/install-bp3.sh`, `completions/_bp3`, `completions/bp3.bash`, `test/skills.sh`, `test/mode.sh`, `test/install.sh` |
| Acceptance | fails today (`bin/bp3` writes all 10 skills + hooks into target repo, no `prune-local`, `install-bp3.sh` doesn't install global skills); passes when all suites pass with strict `$BP3_GLOBAL_HOME` isolation |
| Depends on | `manifest.1 - backpack-toml-parser-and-config` |
| Must not touch | `src/quest/hooks.ml`, `src/warden/*`, `skills/*`, `bp3`'s own `.agents/.claude/.pi` renders (migrated in `skills.1`), `CONSTRAINTS.md`, `Makefile`, `scripts/check-gates` |

## Prose

Note on `skills.1` ordering: in this node (`global.1`), we update `bin/bp3` and `scripts/install-bp3.sh` and test them against isolated fixture repos (`$work/self`, `$work/host`, `$work/home`). We do **not** touch `bp3`'s own tracked `.agents/skills/`, `.claude/skills/`, `.pi/skills/`, or `skills/*.md` yet — `skills.1` performs `bp3`'s own repo migration and skill prose updates in its own dedicated node (per `/quest` step 6.6). Therefore, in `test/skills.sh`, keep the real-checkout assertion compatible during Wave 2 (or check `DEV_SKILLS` exclusions in `$repo/.pi/settings.json`, which is true both before and after `skills.1`!).

Hook command in global hooks: ALWAYS `"bp3 q hooks || true"` (resolved from `PATH`, where `~/.local/bin/bp3` lives), never `"./bin/bp3"` or `"../bin/bp3"`, because global hooks execute from `~/.gemini/config/` or any repo directory on the machine.

In `skills_check`, verify:
1. All 7 `CORE_SKILLS` in global harness dirs (using `$BP3_GLOBAL_HOME` / `$HOME`) match `skills/<s >/SKILL.md` (and `RELEASE` tag if present).
2. In `self` mode, all 3 `DEV_SKILLS` in repo-local `.{agents,claude,pi}/skills/` match `skills/<s>/SKILL.md`.
3. Never fail on hand-written skills or `yap` skills in global dirs.

## Tests

- **Fixture (`test/skills.sh`):** isolated via `BP3_GLOBAL_HOME="$work/home"`; covers global `CORE_SKILLS` install, stale global skill pruning while preserving `yap` (`yap-skills.lock.json` + hand-written skills), non-clobbering merge of `~/.claude/settings.json` and `~/.gemini/config/hooks.json`, `bp3 skills check` fresh vs drifted vs tagged, `self` mode local `DEV_SKILLS`, and `bp3 skills prune-local` preserving repo-owned skills (`/new-strategy`) and non-bp3 hooks.
- **Fixture (`test/mode.sh`):** host mode writes 0 files in `$work/host` and populates global `CORE_SKILLS` + global hooks; self mode writes only `DEV_SKILLS` locally.
- **Fixture (`test/install.sh`):** `scripts/install-bp3.sh` populates `$BP3_GLOBAL_HOME` skills + hooks alongside `$PREFIX/bin/bp3-q` and `$PREFIX/bin/bp3`; `BP3_SKIP_GLOBAL_SKILLS=1` skips global install cleanly.
