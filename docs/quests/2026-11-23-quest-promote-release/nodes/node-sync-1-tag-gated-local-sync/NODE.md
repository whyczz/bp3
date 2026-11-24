---
date: 2026-11-23
quest: ../../QUEST.md
node: sync.1
status: proposed
---

# sync.1 - tag-gated-local-sync: tag-gated `$PREFIX` install + clean host-repo `SessionStart` auto-sync

## TL;DR

Wire tag-gated local auto-update so downstream repos like `~/m/predictor` stay fresh strictly on released `bp3` tags—never on untagged mid-flight commits:
1. `scripts/install-bp3.sh` writes `$PREFIX/share/bp3/RELEASE` (`{"tag":"v<ver>","version":"<ver>","source":"<main_repo>","commit":"<sha>"}`) whenever installing a tagged release.
2. `bp3 release` in `self` mode (`Release_io`) automatically builds and installs the newly tagged release to `$PREFIX` (`make release` + `scripts/install-bp3.sh`, opt-out via `--no-install` or `BP3_RELEASE_NO_INSTALL=1`) right after CAS tagging succeeds, setting `"installed_prefix"` in the verdict JSON (or failing cleanly with `E_INSTALL_FAILED` + `local_tagged: true` if install fails).
3. `bin/bp3 skills install` reads `share/bp3/RELEASE` (when present) and stamps `(v<ver>)` into every rendered `<!-- GENERATED from skills/<name>/SKILL.md (v<ver>) by: ... -->` notice.
4. `src/quest/hooks.ml` (`bp3 q hooks`) runs a host-mode `SessionStart` auto-sync check BEFORE its self-only `bin/bp3` gate: when `repo_mode = "host"`, `BP3_NO_AUTO_SYNC <> "1"`, and `Release.should_auto_sync` sees an installed release tag newer than the repo's rendered skills (or legacy unversioned renders like `predictor`), it checks that the working tree is clean on a normal branch (not detached HEAD, not mid-rebase/merge), runs installed `bp3 skills install --harness=all`, stages ONLY `.claude/`, `.agents/`, `.pi/`, `.muse/`, and commits `chore(bp3): sync skills/hooks to <tag>` (`--no-verify`). When dirty, detached, or rebasing, it touches nothing and emits `W_BP3_UPDATE_AVAILABLE` in the hook verdict.

## Acceptance gates

Observed today (2026-11-23):

```text
$ ls ~/.local/share/bp3/RELEASE
ls: /Users/whycz/.local/share/bp3/RELEASE: No such file or directory
$ grep -n 'GENERATED from skills/' .agents/skills/quest/SKILL.md
5:<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=agy. Edit the source, then re-run. -->
# (no release version tag stamped)
$ grep -n 'not a bp3 repo' src/quest/hooks.ml
257:        if not is_repo then wrap (no_write "not a bp3 repo")
# (host repos without tracked bin/bp3 bail before SessionStart can auto-sync)
```

Design trace (after `sync.1` lands):

```text
# 1. Self-mode release builds & installs tagged release to $PREFIX and writes share/bp3/RELEASE
$ PREFIX=$S BP3_DECIDER=human ./bin/bp3 release demo-self --no-gh
{"ok":true,...,"tag":"v0.3.0","installed_prefix":"<S>",...}
$ cat "$S/share/bp3/RELEASE"
{"tag":"v0.3.0","version":"0.3.0","source":"<repo>","commit":"<sha>"}
$ "$S/bin/bp3-q" --version
0.3.0

# 2. Untagged commit in bp3 repo NEVER updates $S/share/bp3/RELEASE or $S/bin/bp3-q

# 3. Clean host fixture repo (with legacy unversioned skills, matching predictor today):
$ echo '{"hook_event_name":"SessionStart","session_id":"s1"}' | PATH="$S/bin:$PATH" "$S/bin/bp3" q hooks
{"ok":true,...,"auto_sync":{"status":"synced","tag":"v0.3.0","commit":"<sha7>"}}
$ git log -1 --format=%s
chore(bp3): sync skills/hooks to v0.3.0
$ git status --short                         # empty!
$ head -n 6 .agents/skills/quest/SKILL.md    # carries (v0.3.0) in GENERATED notice

# 4. Second SessionStart on already-synced repo -> fast no-op (no new commit)
$ echo '{"hook_event_name":"SessionStart","session_id":"s2"}' | PATH="$S/bin:$PATH" "$S/bin/bp3" q hooks
{"ok":true,...,"auto_sync":{"status":"up_to_date","tag":"v0.3.0"}}

# 5. Dirty host repo (or detached HEAD) with newer release v0.4.0 installed -> skips & warns, zero git writes
$ echo '{"hook_event_name":"SessionStart","session_id":"s3"}' | PATH="$S/bin:$PATH" "$S/bin/bp3" q hooks
{"ok":true,...,"auto_sync":{"status":"dirty_skipped","installed_tag":"v0.4.0","warning":"W_BP3_UPDATE_AVAILABLE"}}
$ git status --short                         # only original dirty file; skills untouched

# 6. BP3_NO_AUTO_SYNC=1 disables auto-sync completely (zero mutations)
$ ./test/release-sync.sh && ./test/hooks.sh && ./test/install.sh && make check-full
```

```yaml
objective: implement tag-gated self-mode install into $PREFIX (writing share/bp3/RELEASE), rendered skill version stamping, and safe clean-only host SessionStart auto-sync with full fixture tests
prove by:
  - ./test/release-sync.sh (registered in test/suites.tsv)
  - ./test/hooks.sh && ./test/install.sh
  - make check-full
done when: self-mode bp3 release updates $PREFIX + RELEASE strictly on tagged releases, clean host repos auto-sync and commit on SessionStart, dirty/detached/opted-out host repos never mutate git, and make check-full exits 0
```

## Diagram

```text
bp3 repo (self mode)
  untagged commit ───────────────────────────► (does NOTHING to $PREFIX)
  bp3 release <q> | --commit <sha> ──► atomic tag v0.3.0
       │ (unless --no-install)
       ▼
  make release + scripts/install-bp3.sh PREFIX=$PREFIX
       └──► $PREFIX/bin/{bp3,bp3-q} + $PREFIX/share/bp3/{skills,RELEASE={"tag":"v0.3.0",...}}

downstream host repo (e.g. ~/m/predictor)
  SessionStart ──► bp3 q hooks (runs BEFORE self-only bin/bp3 gate)
       ├─ BP3_NO_AUTO_SYNC=1 or no share/bp3/RELEASE ──► skip
       ├─ Release.should_auto_sync(installed, rendered) == false ──► status: up_to_date
       └─ newer tag (or legacy unversioned renders):
            ├─ dirty tree OR detached HEAD OR mid-rebase/merge ──► skip + W_BP3_UPDATE_AVAILABLE
            └─ clean tree on refs/heads/*:
                 1. run $PREFIX/bin/bp3 skills install --harness=all (stamps (v0.3.0))
                 2. git add -- .claude .agents .pi .muse (existing dirs only)
                 3. if staged diff non-empty: git commit --no-verify -m "chore(bp3): sync skills/hooks to v0.3.0"
                 4. return hook JSON with auto_sync: {status:"synced", tag, commit} (agy stays valid JSON!)
```

## Pseudocode

```python
def maybe_host_auto_sync(event, gate_root):
    if event != "SessionStart" or getenv("BP3_NO_AUTO_SYNC") == "1":
        return None
    if repo_mode(gate_root) != "host":
        return None
    share = resolve_share_dir()                   # BP3_SHARE_DIR or dirname(exe)/../share/bp3
    rel = read_release_json(share / "RELEASE")    # {"tag": "v0.3.0", ...}
    if not rel or not (installed := Release.parse_semver_tag(rel["tag"])):
        return None
    rendered = scan_rendered_skill_headers(gate_root)   # .claude/skills, .agents/skills, .pi/skills
    if not Release.should_auto_sync(installed, rendered):
        return {"status": "up_to_date", "tag": rel["tag"]}
    if worktree_dirty(gate_root) or not on_symbolic_branch(gate_root) or mid_merge_or_rebase(gate_root):
        return {"status": "dirty_skipped", "installed_tag": rel["tag"], "warning": "W_BP3_UPDATE_AVAILABLE"}
    bp3_bin = resolve_bp3_bin()                   # dirname(exe)/bp3
    if run([bp3_bin, "skills", "install", "--harness=all"], cwd=gate_root) != 0:
        return {"status": "sync_failed", "installed_tag": rel["tag"]}
    stage_existing(gate_root, [".claude", ".agents", ".pi", ".muse"])
    if staged_diff_nonempty(gate_root):
        sha = git_commit_no_verify(gate_root, f"chore(bp3): sync skills/hooks to {rel['tag']}")
        return {"status": "synced", "tag": rel["tag"], "commit": sha[:7]}
    return {"status": "up_to_date", "tag": rel["tag"]}
```

## Tables

| Field | Value |
|---|---|
| Intent | Propagate tagged `bp3` releases safely to `$PREFIX` and clean downstream host repos without ever leaking untagged commits or dirtying active worktrees |
| Lane | standard |
| Output | `scripts/install-bp3.sh` (writes `share/bp3/RELEASE`), `src/quest/release_io.ml` (self-mode auto-install hook on tagged release), `bin/bp3` (stamp `(v<ver>)` in `install_one` from `share/bp3/RELEASE`), `src/quest/hooks.ml` (host `SessionStart` auto-sync before self-only gate; fail-open always exit 0), `test/release-sync.sh`, `test/suites.tsv` |
| Acceptance | `test/release-sync.sh`, `test/hooks.sh`, `test/install.sh`, and `make check-full` exit 0 |
| Depends on | `cli.1 - release-door` |

Safety invariants for host `SessionStart` auto-sync:

| Guard | Behavior |
|---|---|
| Fail-open | `bp3 q hooks` ALWAYS exits `0` (even if `bp3 skills install` or `git commit` fails); never blocks a harness session |
| Harness JSON compatibility | For `agy` (`conversationId` present), keep stdout valid JSON (`agy_reply`) and never print bare prose lines to stdout |
| Clean-tree + branch guard | Requires clean `git status --porcelain`, `git symbolic-ref -q HEAD` under `refs/heads/`, and no `.git/MERGE_HEAD`, `.git/rebase-merge`, `.git/rebase-apply` |
| Scoped staging | Stages ONLY `.claude`, `.agents`, `.pi`, `.muse` (never `git add -A`) |
| `--no-verify` | Skips downstream code formatters (like `predictor`'s `dune build @fmt` pre-commit hook) on pure generated skill/hook sync commits |
| Untagged isolation | `share/bp3/RELEASE` is written ONLY from tagged releases (`scripts/release-check` passes); untagged commits in `bp3` never touch `$PREFIX` or downstream repos |
| Opt-in repos only | `Release.should_auto_sync` returns `false` when `rendered = []` (repos without existing bp3-generated skills are untouched) |
| Kill-switch | `BP3_NO_AUTO_SYNC=1` disables auto-sync cleanly |

## Prose

Notice why `src/quest/hooks.ml` previously skipped host repos: lines 252–257 checked `Sys.file_exists (Filename.concat gate_root "bin/bp3")`, which is only true in `self` mode (`bp3` itself). Running the host `SessionStart` auto-sync check BEFORE that self-only gate keeps all existing `test/hooks.sh` ledger-witnessing behavior unchanged while letting installed `bp3` refresh host repos like `~/m/predictor` seamlessly on `SessionStart` across Claude Code, Muse, and `agy`.

For `scripts/install-bp3.sh`: when `git -C "$root" describe --tags --exact-match HEAD` (or `v$version` at `HEAD`) matches an annotated tag, it writes `$prefix/share/bp3/RELEASE` with `{"tag":"v<version>","version":"<version>","source":"<main_checkout>","commit":"<head_sha>"}`. Note: in `test/release-sync.sh`, to keep fixture runs fast (no `dune build` inside a scratch clone), `bp3 release`'s self-mode install honors an optional `BP3_RELEASE_ARTIFACT=<path>` override (or builds via `make release` by default) so the fixture test runs in `< 2s` while still exercising the real `scripts/install-bp3.sh` + `scripts/release-check` + `share/bp3/RELEASE` + host `SessionStart` path end-to-end!

## Tests

- `test/release-sync.sh` (fixture tier, registered in `test/suites.tsv` with paths `src/*,bin/bp3,scripts/install-bp3.sh,test/release-sync.sh`):
  1. Self-mode `bp3 release` with `PREFIX=$work/prefix` builds/installs tagged release and writes `$PREFIX/share/bp3/RELEASE` with `tag: "v0.3.0"`.
  2. `--no-install` skips `$PREFIX` update cleanly.
  3. Clean host repo with legacy unversioned skills (matching `predictor`): `SessionStart` auto-runs `bp3 skills install --harness=all`, stamps `(v0.3.0)` in `.claude/skills/`, `.agents/skills/`, `.pi/skills/`, commits `chore(bp3): sync skills/hooks to v0.3.0`, leaves `git status` empty, and survives a failing host `.git/hooks/pre-commit` (`exit 1`) because of `--no-verify`.
  4. Second `SessionStart` is a fast no-op (`status: "up_to_date"`, HEAD SHA unchanged).
  5. Newer release `v0.4.0` installed while host repo has dirty tracked file -> `status: "dirty_skipped"`, `warning: "W_BP3_UPDATE_AVAILABLE"`, skills and git history untouched.
  6. Detached HEAD or mid-rebase host repo -> `dirty_skipped`, zero mutations.
  7. `BP3_NO_AUTO_SYNC=1` -> zero mutations.
  8. `agy` `SessionStart` payload (`conversationId` present) -> valid JSON on stdout, exit 0.
  9. Host repo with zero bp3-generated skills -> never creates `.claude/skills`.
- `test/hooks.sh` and `test/install.sh`: stay 100% green.
