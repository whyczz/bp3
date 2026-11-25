---
date: 2026-11-25
quest: ../../QUEST.md
node: global.2
status: proposed
---

# global.2 - hooks-backpack-gate-and-retire-autosync: re-root `hooks.ml` on `payload.cwd`, gate on `backpack.toml`, retire host auto-commit sync

## TL;DR

Make user-global `bp3 q hooks` work identically across every `bp3` repo (self and host) while staying strictly dormant in non-bp3 repos: resolve `gate_root` from `payload.cwd` (falling back to `payload.workspacePaths[0]`, then `Gitx.root`) and re-root all git/registry/run operations in `src/quest/hooks.ml` onto `gate_root` so invoking `bp3 q hooks` from `cwd = ~/.gemini/config/` works cleanly; replace the self-only `bin/bp3` gate with `Sys.file_exists (Filename.concat gate_root Layout.manifest_file)` (keeping legacy `bin/bp3 && docs/quests` fallback only until `skills.1` commits `bp3/backpack.toml`); and retire `maybe_host_auto_sync`'s `git add` / `git commit` mutation in favor of a read-only `W_LOCAL_SKILLS_LEGACY` warning when stale local generated skill copies remain in a host repo.

## Acceptance gates

Observed today (`2026-11-25`, `a7087eb`):

```text
$ grep -n 'maybe_host_auto_sync\|chore(bp3): sync' src/quest/hooks.ml
284:let maybe_host_auto_sync gate_root =
322:                                        "-m"; "chore(bp3): sync skills/hooks to " ^ tag_str ] in
374:            match maybe_host_auto_sync gate_root with
$ grep -n 'Filename.concat gate_root "bin/bp3"' src/quest/hooks.ml
368:          Sys.file_exists (Filename.concat gate_root "bin/bp3") &&
```

Design trace:

```text
$ # 1. Global hook invoked with process PWD=/tmp (simulating ~/.gemini/config/), payload cwd = host repo with backpack.toml:
$ (cd /tmp && printf '{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=R1 BP3_QUEST=q1 BP3_NODE=n1 ./run"}}\n' "$repo" | bp3-q q hooks)
{"ok":true,"event_line":{...,"event":"run_started",...},"reason":null}

$ # 2. Same hook invoked with payload cwd = non-bp3 repo (no backpack.toml):
$ (cd /tmp && printf '{"hook_event_name":"SessionStart","session_id":"s2","cwd":"%s"}\n' "$other_repo" | bp3-q q hooks)
{"ok":true,"event_line":null,"reason":"not a bp3 repo"}

$ # 3. SessionStart in host repo with leftover local generated skills: NEVER git commits!
$ before=$(git -C "$legacy_host" rev-parse HEAD)
$ printf '{"hook_event_name":"SessionStart","session_id":"s3","cwd":"%s"}\n' "$legacy_host" | bp3-q q hooks
{"ok":true,"event_line":null,"reason":...,"warnings":[{"code":"W_LOCAL_SKILLS_LEGACY","message":"...bp3 skills prune-local..."}]}
$ [ "$(git -C "$legacy_host" rev-parse HEAD)" = "$before" ]  # zero commits!

$ # 4. Self-mode bp3 release still auto-installs binary + global skills/hooks into $PREFIX & $BP3_GLOBAL_HOME
$ ./test/hooks.sh && ./test/release-sync.sh && dune test && make check-full  # rc 0
```

```yaml
objective: re-root bp3 q hooks onto payload.cwd gate_root, gate activation on backpack.toml, and replace host SessionStart auto-commit skill sync with read-only W_LOCAL_SKILLS_LEGACY detection
prove by:
  - test/hooks.sh: invoking bp3 q hooks from cd /tmp with payload cwd pointing at a backpack.toml repo binds and emits run_started/lint_checked/run_settled into that repo's ledger; repo without backpack.toml returns reason "not a bp3 repo" with zero writes; agy workspacePaths fallback works when cwd is omitted
  - test/release-sync.sh: self-mode bp3 release installs binary + global skills/hooks into $PREFIX + $BP3_GLOBAL_HOME and stamps RELEASE; host SessionStart with legacy local generated skills emits W_LOCAL_SKILLS_LEGACY and creates ZERO git commits; clean host repo with backpack.toml and no local generated skills emits 0 warnings
  - test/unit/test_hooks.ml & test/unit/test_release.ml: pure unit coverage for gate_root resolution, legacy local skill detection, and retired auto-sync cleanup
  - make check && make check-full
done when: all unit and fixture suites pass, global hooks work from any process cwd via payload.cwd, and hooks.ml contains zero git add / git commit auto-sync code
```

## Diagram

```text
Global hook fires (process PWD may be ~/.gemini/config/ or ~/.claude/)
  │
  ▼
Hooks.handle () reads stdin JSON
  │
  ├── resolve gate_root from payload.cwd (else payload.workspacePaths[0], else Gitx.root)
  │     └── git -C <raw> rev-parse --show-toplevel
  │
  ├── check backpack.toml at gate_root  (transition fallback: bin/bp3 && docs/quests)
  │     ├── ABSENT  ──► exit 0, {"ok":true,"event_line":null,"reason":"not a bp3 repo"} (0 writes)
  │     └── PRESENT ──► re-root Gitx/registry/runs to gate_root (Unix.chdir gate_root + set_root)
  │                       ├── SessionStart: sweep stale bindings; if host has leftover local
  │                       │   "<!-- GENERATED from skills/" files -> attach W_LOCAL_SKILLS_LEGACY
  │                       │   (STRICTLY READ-ONLY on git — ZERO git add/commit!)
  │                       └── PreToolUse / PostToolUse / Stop / SessionEnd / ...
  │                             └── witness run_started / refused / lint_checked / run_settled
```

## Pseudocode

```python
# src/quest/hooks.ml
def payload_cwd(j) -> str:
    c = member_str(j, "cwd")
    if c:
        return c
    ws = member_list(j, "workspacePaths")
    if ws and isinstance(ws[0], str) and ws[0]:
        return ws[0]
    return Gitx.current_root()

def resolve_gate_root(raw: str) -> str:
    if raw and exists(raw):
        top, rc = run_capture(["git", "-C", raw, "rev-parse", "--show-toplevel"])
        if rc == 0 and top:
            return top
    return raw

def is_bp3_repo(gate_root: str) -> bool:
    return (
        exists(f"{gate_root}/{Layout.manifest_file}")
        or (exists(f"{gate_root}/bin/bp3") and any(is_dir(f"{gate_root}/{r}") for r in quests_roots))
    )

def detect_legacy_local_skills(gate_root: str) -> list[str]:
    if not is_host_git_repo(gate_root):
        return []
    # scan .claude/skills, .agents/skills, .pi/skills for "<!-- GENERATED from skills/"
    # return matching relative paths (empty list -> no warning)

def handle():
    # ... parse stdin, resolve gate_root ...
    if not is_bp3_repo(gate_root):
        # Even if backpack.toml isn't created yet, if a legacy host repo has local generated
        # skills on SessionStart, emit read-only W_LOCAL_SKILLS_LEGACY (never git commit!).
        if event == "SessionStart" and detect_legacy_local_skills(gate_root):
            return wrap(verdict_with_warning("W_LOCAL_SKILLS_LEGACY", ...))
        return wrap(no_write("not a bp3 repo"))
    Gitx.retarget_root(gate_root)  # updates git_root ref + invalidates ref caches
    # proceed with existing hook event handling using gate_root!
```

## Tables

| Field | Value |
|---|---|
| Intent | make global `bp3 q hooks` re-root cleanly on `payload.cwd`, activate via `backpack.toml`, and retire host `SessionStart` git auto-commits |
| Lane | high-blast-radius |
| Output | `src/quest/gitx.ml` (retargetable root helper for hooks), `src/quest/names.ml` (`w_local_skills_legacy`), `src/quest/hooks.ml`, `src/quest/release.ml` (remove unused `should_auto_sync` if dead), `test/unit/test_hooks.ml`, `test/unit/test_release.ml`, `test/hooks.sh`, `test/release-sync.sh` |
| Acceptance | fails today (`hooks.ml` gates on `bin/bp3`, uses process `Gitx.root` for registry/runs, and auto-commits host skill dirs via `maybe_host_auto_sync`); passes when global hooks work from `cd /tmp` and zero git auto-commits occur |
| Depends on | `manifest.1 - backpack-toml-parser-and-config`, `global.1 - global-skills-and-hooks-installer` |
| Must not touch | `bin/bp3`, `scripts/install-bp3.sh`, `src/warden/*`, `skills/*`, `CONSTRAINTS.md`, `Makefile`, `scripts/check-gates` |

## Prose

Why `Gitx.retarget_root` matters: `Gitx.root` is currently computed once at process startup from `BP3_ROOT` or `Sys.getcwd ()`. When `agy` runs a global hook from `~/.gemini/config/hooks.json`, `Sys.getcwd ()` is `~/.gemini/config/` (not a git repo!) and `BP3_ROOT` is unset. Adding a clean `Gitx.set_root dir` (only called by `Hooks.handle` right after `gate_root` is validated) lets `git_dir ()`, `run_dir`, `load_registry ()`, `save_registry`, and `Store.commit_files` all operate on `gate_root` without rewriting every helper signature.

Keep the `agy` reply contract (`agy_reply event`) intact: `PreToolUse` returns `{"decision":"allow"}` and other events return `{}` when `conversationId` is present, so `agy` never rejects a hook response.

Retiring `maybe_host_auto_sync` deletes ~90 lines of fragile git-mutating code from `hooks.ml` (`host_can_auto_commit`, `git add`, `git commit --no-verify`). Because `scripts/install-bp3.sh` (called by `bp3 release` in `global.1`) now refreshes user-global skills and hooks immediately upon release, host repos stay permanently in lockstep with `$PREFIX/bin/bp3` without touching a single host git branch.

## Tests

- **Unit (`test/unit/test_hooks.ml`, `test/unit/test_release.ml`):** `payload_cwd` fallback (`cwd` -> `workspacePaths[0]` -> root), `W_LOCAL_SKILLS_LEGACY` detection, cleanup of retired `should_auto_sync` tests.
- **Fixture (`test/hooks.sh`):** invoke `bp3 q hooks` from `cd /tmp` (outside any git repo!) against a repo with `backpack.toml` and verify full event emission (`run_started`, `lint_checked`, `run_settled`), plus dormant `not a bp3 repo` check on a git repo without `backpack.toml`.
- **Fixture (`test/release-sync.sh`):** verify self-mode `bp3 release` updates `$PREFIX` AND `$BP3_GLOBAL_HOME` global skills + hooks; verify host `SessionStart` with legacy local generated skills emits `W_LOCAL_SKILLS_LEGACY` and creates zero git commits.
