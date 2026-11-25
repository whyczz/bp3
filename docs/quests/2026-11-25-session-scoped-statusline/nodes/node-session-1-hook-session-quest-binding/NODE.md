---
date: 2026-11-25
quest: ../../QUEST.md
node: session.1
status: proposed
---

# session.1 - hook-session-quest-binding: write `<git-common-dir>/bp3/sessions/<sid>.json` from `bp3 q hooks` (self & host repos)

## TL;DR

Add pure session-binding extraction and safe atomic persistence (`<canon(git_common_dir)>/bp3/sessions/<sanitized_sid>.json`) to `src/quest/hooks.ml` so `PreToolUse` / `PostToolUse` automatically track which quest each session is working on (`bp3 harness desk prepare --quest <q>`, `bp3 q <q> ...`, or editing `docs/quests/<q>/QUEST.{red-ink,2b-reviewed}.md`), clear the binding on `bp3 release <q>` (non-`--dry-run`), and prune stale bindings (>24h) on `SessionStart` — working in **both** self and host repos, strictly fail-open, with unit + QCheck2 tests in `test/unit/test_hooks.ml` and fixture tests in `test/hooks.sh`.

## Acceptance gates

Observed today (2026-11-25, `2ca58e09`):

```text
$ rg -n 'bp3/sessions|session_binding|session_ttl' src/quest/hooks.ml
# 0 matches
$ rg -n 'bin/bp3' src/quest/hooks.ml
368:          Sys.file_exists (Filename.concat gate_root "bin/bp3") &&
# Host repos without bin/bp3 return "not a bp3 repo" on PreToolUse/PostToolUse today.
```

Design trace:

```text
# 1. Bind session on quest desk prepare (self OR host repo):
$ printf '{"conversationId":"conv-A","hookEventName":"PostToolUse","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 harness desk prepare --quest q-alpha"}}}\n' "$repo" | bp3 q hooks
{}
# <git-common-dir>/bp3/sessions/conv-A.json -> {"session_id":"conv-A","quest":"q-alpha","mode":"induct","desk":null,"red_ink_path":null,"updated_ts":...}

# 2. Bind parallel session on red-ink working copy edit:
$ printf '{"conversationId":"conv-B","hookEventName":"PostToolUse","cwd":"%s","toolCall":{"name":"edit_file","args":{"Path":"%s/docs/quests/q-beta/QUEST.red-ink.md"}}}\n' "$repo" "$repo" | bp3 q hooks
{}
# <git-common-dir>/bp3/sessions/conv-B.json -> {"session_id":"conv-B","quest":"q-beta","mode":"red-ink","red_ink_path":"docs/quests/q-beta/QUEST.red-ink.md",...}

# 3. Clear conv-A on `bp3 release q-alpha` (conv-B stays untouched; `--dry-run` does NOT clear):
$ printf '{"conversationId":"conv-A","hookEventName":"PostToolUse","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha"}}}\n' "$repo" | bp3 q hooks
{}
# conv-A.json unlinked; conv-B.json still exists!

# 4. Stale >24h session JSON pruned on SessionStart; fresh session JSON kept.
$ dune test && ./test/hooks.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: automatically maintain per-session quest bindings in <git-common-dir>/bp3/sessions/<sid>.json via bp3 q hooks for both self and host repos, with clear-on-release and 24h GC on SessionStart
prove by:
  - test/unit/test_hooks.ml: unit cases for command/path extraction (desk prepare --quest, bp3 q <q>, bp3 release <q>, --dry-run ignored, bare bp3 q r ignored, red-ink/2b-reviewed file path extraction) + QCheck2 law proving sanitize_session_id never contains '/' or '..' or leading '.'
  - test/hooks.sh: live fixture tests in BOTH self and host repos proving bind, parallel 2-session isolation, red-ink bind, release clear (non-dry-run only), 24h stale GC on SessionStart, agy PreToolUse {"decision":"allow"} / PostToolUse {} preserved, and zero repo dirt
  - make check && make check-full (25/25 suites)
done when: hooks maintain isolated session quest bindings safely across self and host repos, never touch tracked files or block tools, and all unit + 25 fixture suites pass
```

## Diagram

```text
bp3 q hooks (stdin JSON: session_id / conversationId, cwd, command / file_path)
  ├── git rev-parse --git-common-dir (in gate_root) + docs/quests/ exists?
  │     ├── NO  ──► existing host auto-sync / no_write (untouched)
  │     └── YES ──► session_dir = <canon(common_dir)>/bp3/sessions
  │                   ├── SessionStart ──► prune *.json older than 86400s
  │                   └── PreToolUse / PostToolUse:
  │                         ├── `bp3 release <q>` (no --dry-run) ──► unlink <sid>.json
  │                         ├── `bp3 harness desk prepare --quest <q>`
  │                         │   or `bp3 worktree prepare --quest <q>`
  │                         │   or `bp3 q <q> <subcmd>` (valid slug) ──► write {quest:q, mode:"induct"}
  │                         └── edit/write `docs/quests/<q>/QUEST.{red-ink,2b-reviewed}.md`
  │                                                                ──► write {quest:q, mode:"red-ink", red_ink_path}
  └── continue existing self-mode run-witness logic unchanged (always exit 0)
```

## Pseudocode

```python
SESSION_TTL_S = 86400

def sanitize_session_id(sid: str) -> str | None:
    if not sid or len(sid) > 128 or sid[0] == "." or ".." in sid:
        return None
    if all(c.isalnum() or c in "._-" for c in sid):
        return sid
    return None

def extract_session_action(command: str, file_path: str):
    # 1. File-edit tools touching docs/quests/<q>/QUEST.red-ink.md or QUEST.2b-reviewed.md
    if file_path:
        m = re.search(r"docs/quests/([a-z0-9][a-z0-9-]*)/(QUEST\.(?:red-ink|2b-reviewed)\.md)$", file_path)
        if m:
            return ("bind", m.group(1), "red-ink", f"docs/quests/{m.group(1)}/{m.group(2)}")
    if not command:
        return None
    # 2. bp3 release <q> (ignore --dry-run and --commit)
    if "bp3" in command and " release " in command and "--dry-run" not in command and "--commit" not in command:
        q = token_after(command, "release")
        if valid_slug(q):
            return ("clear", q)
    # 3. bp3 (harness desk|worktree) prepare --quest <q>
    if "prepare" in command and "--quest" in command:
        q = token_after(command, "--quest")
        if valid_slug(q):
            return ("bind", q, "induct", None)
    # 4. bp3 q <q> ... (skip reserved verbs: c, r, hooks, metrics, help, -h; allow `bp3 q c <q>` and `bp3 q r <q>` and `bp3 q <q> ...`)
    q = extract_bp3_q_quest(command)
    if q and valid_slug(q):
        return ("bind", q, "induct", None)
    return None

def update_session_binding(gate_root, sid, event, command, file_path):
    clean_sid = sanitize_session_id(sid)
    if not clean_sid:
        return
    sdir = canon_common_dir(gate_root) + "/bp3/sessions"
    if event == "SessionStart":
        prune_older_than(sdir, now() - SESSION_TTL_S)
    elif event in ("PreToolUse", "PostToolUse"):
        act = extract_session_action(command, file_path)
        if act == ("clear", q):
            unlink_if_matches_quest(f"{sdir}/{clean_sid}.json", q)
        elif act and act[0] == "bind":
            mkdir_p(sdir)
            write_file_atomic(f"{sdir}/{clean_sid}.json", json_encode(...))
```

## Tables

| Field | Value |
|---|---|
| Intent | give every terminal/agent session an automatic, isolated quest bookmark in `<git-common-dir>/bp3/sessions/<sid>.json` across self and host repos |
| Lane | standard |
| Output | `src/quest/hooks.ml`, `test/unit/test_hooks.ml`, `test/hooks.sh` |
| Acceptance | fails today (no `bp3/sessions/` writer in `hooks.ml` and host repos exit early); passes when unit, QCheck2, `test/hooks.sh`, and `make check-full` pass |
| Depends on | none |
| Must not touch | `scripts/agy-statusline`, `skills/*`, `CONSTRAINTS.md`, `src/quest/release_io.ml` |

## Prose

Why run session binding on `PostToolUse` AND `PreToolUse` (Wait: what about `bp3 release <q>`?):
- Binding on `PreToolUse` gives instant statusline updates while a long command (like `bp3 harness desk prepare`) is running, AND `PostToolUse` updates the timestamp.
- For `bp3 release <q>`, clear ONLY on `PostToolUse` (when `error` is empty / not `PostToolUseFailure`), so a failed or refused `bp3 release` does NOT prematurely clear the session's quest binding!
- Extract `file_path` from both Claude Code (`tool_input.file_path` / `tool_input.path`) and agy (`toolCall.args.Path` / `toolCall.args.TargetFile`), so `edit_file` / `write_file` / `Write` / `Edit` all bind `[red-ink]` automatically.

## Tests

- **Known cases (`test/unit/test_hooks.ml`):** `extract_session_action` over `bp3 harness desk prepare --quest q1`, `./bin/bp3 q q1 n node-1 e handoff`, `./bin/bp3 q c q1`, `./bin/bp3 q r q1`, bare `./bin/bp3 q r` (None), `./bin/bp3 warden q1` (None), `BP3_DECIDER=human ./bin/bp3 release q1` (clear), `bp3 release q1 --dry-run` (None), `edit_file` on `docs/quests/q1/QUEST.red-ink.md` (red-ink bind), `edit_file` on `docs/quests/q1/QUEST.md` (None).
- **Property-based (QCheck2 in `test/unit/test_hooks.ml`):** `sanitize_session_id` returns `Some s` ONLY when `s` contains no `/`, `\`, `..`, or leading `.` and has length `1..128`.
- **Fixture tests (`test/hooks.sh`):** self repo + host repo (no `bin/bp3`), two concurrent sessions `conv-A` and `conv-B`, release clear (PostToolUse success clears, PostToolUseFailure / `--dry-run` keeps), and `SessionStart` pruning a backdated >24h session file while preserving a fresh one.
