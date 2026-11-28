---
node: skills.1
slug: ocaml-skills-installer-lib
kind: code
lane: standard
status: proposed
depends_on: []
---

# skills.1 - ocaml-skills-installer-lib

TL;DR
Build the `bp3_skills` OCaml library (`src/skills/{dune,skills.ml,skills_io.ml}`) covering 100% of `bin/bp3`'s skill/hook management (`skills install [--global] [--harness=...]`, `skills check`, `skills prune-local`), with byte-identical render output, non-clobbering `Yojson.Safe` hook/settings merges, executable-relative `share/bp3/` resolution, and unit + QCheck2 tests in `test/unit/test_skills.ml`.

## Acceptance gates

Design trace:

```text
# 1. Pure render parity & round-trip
Skills.render_skill ~skill:"warden" ~harness:"agy" ~release_tag:(Some "v0.13.0") src
  -> inserts "<!-- GENERATED from skills/warden/SKILL.md (v0.13.0) by: bp3 skills install --harness=agy. Edit the source, then re-run. -->" immediately after second "---" line
Skills.strip_generated_notice rendered = src

# 2. Non-clobbering hook JSON merges (Claude, Muse, agy) + idempotence
Skills.plan_claude_hooks_merge ~hook_cmd:"bp3 q hooks || true" ~include_post_llm:false existing
  -> keeps custom keys & custom hooks, upserts bp3 hook across 8 events (9 with PostLLMCall for Muse)
Skills.plan_agy_hooks_merge ~hook_cmd:"bp3 q hooks || true" existing
  -> keeps unrelated top-level keys, upserts only "bp3" object

# 3. Safe prune-local JSON surgery (never touches non-bp3 hooks/skills; returns None when object becomes {})
Skills.plan_prune_claude_settings j -> Ok (Some cleaned) | Ok None
Skills.plan_prune_agy_hooks j       -> Ok (Some cleaned) | Ok None
Skills.plan_prune_pi_settings ~drop_skills j -> Ok (Some cleaned) | Ok None

# 4. Unit + QCheck2 suite passes
$ dune test test/unit/test_skills.exe
Ran N tests ... OK
```

Runnable goal block:
- **objective:** Implement `bp3_skills` (`src/skills/`) with full feature & byte-level parity against `bin/bp3`'s `skills_install`, `skills_check`, and `skills_prune_local`, verified by unit + QCheck2 tests.
- **prove by:** `dune build src/skills/` and `dune test` (`test/unit/test_skills.ml`), plus `make check`.
- **done when:** `make check-full` passes with `test/unit/test_skills.ml` covering render parity, freshness checks, hook merge preservation/idempotence, `prune-local` JSON surgery, `--mode` rejection, skill-set completeness, and QCheck2 laws.

## Diagram

```text
src/skills/skills.ml (pure, zero I/O)
  |-- core_skills / dev_skills / retired_workflows / retired_skills (single source of truth)
  |-- render_skill / strip_generated_notice / generated_notice_line / is_render_fresh
  |-- plan_claude_hooks_merge / plan_agy_hooks_merge / plan_pi_settings_merge
  |-- plan_prune_claude_settings / plan_prune_agy_hooks / plan_prune_pi_settings
  +-- check_verdict_json / prune_verdict_json

src/skills/skills_io.ml (filesystem + git + Repo_io)
  |-- resolve_paths (BP3_SKILLS_DIR / BP3_CHECK_SKILLS / BP3_SHARE_DIR -> BP3_SELF_ROOT -> <exe_dir>/../share/bp3)
  |-- resolve_target_root (BP3_TARGET -> cwd git toplevel -> BP3_SELF_ROOT -> cwd)
  |-- preflight check-skills -> plan all JSON merges -> write atomically -> prune stale
  +-- run_install / run_check / run_prune_local -> int exit code (0 | 1 | 2)
```

## Pseudocode

```python
CORE_SKILLS = ["induct", "induct-yolo", "quest", "icebox", "naming", "red-ink", "warden"]
DEV_SKILLS = ["add-bp3-skill", "add-yap-skill", "using-bp3"]
ALL_HARNESSES = ["pi", "claude", "codex", "muse", "agy"]

def render_skill(skill: str, harness: str, release_tag: str | None, src: str) -> str:
    tag = f" ({release_tag})" if release_tag else ""
    notice = f"<!-- GENERATED from skills/{skill}/SKILL.md{tag} by: bp3 skills install --harness={harness}. Edit the source, then re-run. -->"
    # Insert notice line right after the 2nd exact "---" line, preserving trailing newline.
    ...

def resolve_share_root(exe_path: str, self_root: str | None) -> str:
    # 1. Explicit BP3_SHARE_DIR if set
    # 2. If self_root has skills/ -> self_root (repo dev layout)
    # 3. <dirname(realpath(exe_path))>/../share/bp3 (installed $PREFIX/bin/bp3 layout)
    # 4. Fallback <dirname(realpath(exe_path))>/..
    ...

def run_install(argv: list[str]) -> int:
    # 1. Reject --mode / --mode=* with exit 2 ("mode is derived from the repo ...")
    # 2. Parse --global, --harness=<h> | --harness <h>; validate all harnesses
    # 3. Preflight check-skills BEFORE writing any file
    # 4. Plan all hook JSON merges (claude, agy, muse) & self-mode .pi/settings.json BEFORE writing
    # 5. Install global CORE_SKILLS + prune stale global generated dirs + atomic hook writes
    # 6. If self mode & not --global: install local DEV_SKILLS, prune stale local, write .pi/settings.json, prune retired workflows
    # 7. Deliver completions (unless --global or BP3_SKIP_COMPLETIONS=1)
    # 8. Auto-register git repo via Repo_io.add (unless --global)
    ...
```

## Fields

| Field | Value |
|---|---|
| Intent | Create `bp3_skills` OCaml library implementing all skill/hook install, check, and prune-local logic with unit + QCheck2 tests |
| Kind | `code` |
| Lane | `standard` |
| Output | `src/skills/{dune,skills.ml,skills_io.ml}`, `test/unit/test_skills.ml`, `test/unit/dune`, updated `scripts/check-retired-terms.sh` allowlist |
| Acceptance | Fails today (`src/skills/` and `test/unit/test_skills.ml` do not exist); passes when `dune test` + `make check-full` pass with all parity and QCheck2 laws green |
| Depends on | none |

## Prose & edge cases

- **Byte-identical renders:** Match `bin/bp3:130-139` (`awk`) exactly, including trailing newline behavior and exact `<!-- GENERATED from skills/<skill>/SKILL.md [(tag)] by: bp3 skills install --harness=<h>. Edit the source, then re-run. -->` format, so committed `.{agents,claude,pi}/skills/*/SKILL.md` files do not churn.
- **Spaces in paths:** `test/skills.sh:38` uses `"$work/project with spaces"`. Pass `argv` directly via `Unix.create_process` (never shell string interpolation) when invoking `check-skills` or `git`.
- **Non-clobbering & preflight atomicity:** Validate `check-skills`, harness names, and all existing target JSON files (`~/.claude/settings.json`, `~/.gemini/config/hooks.json`, `~/.muse/hooks.json`, `.pi/settings.json`) BEFORE creating any directory or writing any file (`test/skills.sh:59-62,80-81` asserts `.pi`/`.agents`/`.claude` are NOT created on failure!).
- **Pretty JSON formatting:** Write JSON with `Yojson.Safe.pretty_to_string` + trailing `\n` via temp file in same directory + `Unix.rename` (atomic, never truncates target on failure).
- **Check `scripts/check-retired-terms.sh`:** Add `src/skills/skills.ml` to the retired-terms allowlist (alongside `bin/bp3` until `cli.1` removes `bin/bp3`'s copy) so `make lint` passes in this node.
- **In-process `Repo_io.add`:** Library `bp3_skills` depends on `bp3_quest`, `bp3_repo`, `yojson`, `unix`. For auto-registration (step 5 of `skills_install`), call `Repo_io` directly when `not global_only` and target is a git repo (matching `bin/bp3:370-381`, fail-fast on error).
- **Tests (`test/unit/test_skills.ml`):**
  - *Known cases:* render with/without `release_tag`; `strip_generated_notice` & `is_render_fresh` (fresh, stale body, mismatched tag, missing notice); `plan_claude_hooks_merge` (preserves custom keys + custom hooks, replaces old bp3 hook without duplicating, Muse includes `PostLLMCall`); `plan_agy_hooks_merge` (preserves other top-level keys, upserts `"bp3"`); `plan_pi_settings_merge` (preserves unrelated entries, drops retired/core exclusions, appends missing dev exclusions); `plan_prune_*` (returns `None` when object empties to `{}` vs `Some` when user keys remain); `--mode` refusal message; skill-set completeness against repo `skills/*`.
  - *Property-based (QCheck2):* (1) For arbitrary frontmatter + body markdown strings, `strip_generated_notice (render_skill ~skill ~harness ~release_tag src) = src`; (2) `plan_claude_hooks_merge` and `plan_agy_hooks_merge` are idempotent (`plan (plan j) = plan j`) and never drop arbitrary unrelated keys/hooks.
