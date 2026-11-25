---
status: active
home_repo: bp3
date: 2026-11-25
bump: minor
---

# session-scoped-statusline: bind each terminal/agy session to its own quest so parallel sessions never hijack the statusline

TL;DR
Make `scripts/agy-statusline` session-scoped instead of repo-global: `bp3 q hooks` (`PreToolUse`/`PostToolUse` in `src/quest/hooks.ml`) records a lightweight machine-local binding `<git-common-dir>/bp3/sessions/<session_id>.json` whenever a session works on a quest (`bp3 harness desk prepare --quest <q>`, `bp3 q <q> ...`, or editing `docs/quests/<q>/QUEST.{red-ink,2b-reviewed}.md`), clears it on `bp3 release <q>`, and prunes stale bindings (>24h) on `SessionStart`. `scripts/agy-statusline` resolves the session ID from stdin JSON first — so parallel terminals each show their own quest and an abandoned `.2b-reviewed.md` file never freezes unrelated sessions.

ELI5
Previously, the statusline looked at the repo as a whole: if you opened three terminals on `bp3` and an old `QUEST.2b-reviewed.md` file sat anywhere in `docs/quests/`, *every* terminal froze on `[red-ink]` for that dead file, and two sessions working on different quests couldn't tell which quest belonged to which terminal. Now each terminal's own session ID gets a tiny local bookmark in `.git/bp3/sessions/<id>.json` automatically as you run `bp3` commands, so each terminal displays only its own quest (or `bp3: idle`).

## Context

Owner direction (2026-11-25):
- *"the statusline for agy for bp3 is frozen at `bp3: 2026-11-23-dag-fsm-v2 [red-ink]`, why? can we make statusline tied to a session, e.g. since each terminal/agy session will be doing its own thing."*
- Split cleanly from `2026-11-25-desk-auto-cleanup` as its own focused quest. (The stale `docs/quests/2026-11-23-dag-fsm-v2/QUEST.2b-reviewed.md` file was deleted immediately on 2026-11-25 for instant relief, while this quest fixes the underlying repo-global architecture permanently.)

Measured ground (audited 2026-11-25 on `master` `2ca58e09`, `v0.6.0`):

| Fact | Source |
|---|---|
| `scripts/agy-statusline:83-91` parses only `workspace.current_dir`/`cwd` and `context_window.*` from stdin JSON — it never reads `session_id`, `conversation_id`, `conversationId`, or `transcript_path` | `scripts/agy-statusline:79-93` |
| `scripts/agy-statusline:146-165` checks (1) `quest/*` branch (always misses when main checkout stays on `master` under central `~/.bp3/desks/`), then (2) globs `docs/quests/*/QUEST.red-ink.md` and `QUEST.2b-reviewed.md` repo-wide — allowing one abandoned file to hijack every session | `scripts/agy-statusline:146-177` |
| `src/quest/hooks.ml:346-357` already extracts `session_id` (Claude) and `conversationId` (agy), plus `command_of` (`tool_input.command` / `toolCall.args.CommandLine`), and runs on every `PreToolUse` / `PostToolUse` / `SessionStart` | `src/quest/hooks.ml:43-58,346-360` |
| `src/quest/hooks.ml:367-381` currently exits early (`"not a bp3 repo"`) on `PreToolUse`/`PostToolUse` in host repos (because `bin/bp3` is absent), so session quest binding must check `docs/quests` (or `git_common_dir`), not `bin/bp3`, to work in host repos like `~/m/predictor` too | `src/quest/hooks.ml:367-381` |
| `test/agy-statusline.sh:51-77` sends payloads without `session_id` and tests repo-global `QUEST.red-ink.md` precedence | `test/agy-statusline.sh:51-77` |

## Terms

| Term | Meaning |
|---|---|
| `session_id` | unique identifier for the current terminal/agent conversation (`session_id` in Claude Code, `conversationId` / `conversation_id` in agy, or extracted from `transcript_path` when omitted) |
| `session_dir` | `<canon(git_common_dir)>/bp3/sessions` — machine-local directory holding one `<sanitized_session_id>.json` file per active session (shared across main checkout and all central `~/.bp3/desks/` worktrees, zero repo dirt) |
| `session_binding` | JSON record `{ "session_id", "quest", "mode": "induct"|"red-ink", "desk": string|null, "red_ink_path": string|null, "updated_ts": int }` written atomically via `Util.write_file_atomic` |
| `session_ttl_s` | `86400` (24 hours) — stale session files older than `session_ttl_s` are pruned automatically on `SessionStart` |

## Inputs

| Input | Source & precedence |
|---|---|
| `bp3 q hooks` stdin JSON (`PreToolUse`, `PostToolUse`, `SessionStart`) | Claude (`session_id`, `tool_input.command`, `tool_input.file_path`) and agy (`conversationId`, `toolCall.args.CommandLine`, `toolCall.args.Path`) |
| `scripts/agy-statusline` stdin JSON | `.session_id // .conversation_id // .conversationId`, falling back to `<conv-id>` extracted from `.transcript_path` (e.g. `.../brain/<conv-id>/...` or `.../<sid>.jsonl`), else empty (legacy branch/active fallback) |
| `<git-common-dir>/bp3/sessions/<sid>.json` | machine-local per-session binding written by `bp3 q hooks` and read by `scripts/agy-statusline` in `<2ms` via `jq` |
| `git rev-parse --git-common-dir` | anchors `session_dir` identically from main checkout or any central `~/.bp3/desks/` worktree |

## Outputs

| Output | Shape |
|---|---|
| `<git-common-dir>/bp3/sessions/<sid>.json` | atomic JSON binding (`session_id`, `quest`, `mode`, `desk`, `red_ink_path`, `updated_ts`); unlinked on `bp3 release <q>` or pruned after 24h |
| `scripts/agy-statusline` stdout | one ANSI line scoped to THIS session's quest (or `bp3: idle` when session is present and unbound), always exit 0 (fail-open) |
| `bp3 q hooks` stdout | unchanged fail-open JSON protocol (`{"decision":"allow"}` for agy `PreToolUse`, `{}` for other agy events, standard verdict for Claude) |

## Acceptance gates

Observed today (2026-11-25, `master` `2ca58e09`, `v0.6.0`):

```text
$ rg -n 'session_id|conversation_id|bp3/sessions' scripts/agy-statusline
# 0 matches
# Today: planting any docs/quests/old-q/QUEST.2b-reviewed.md causes EVERY session in the repo to print:
#   bp3: old-q [red-ink] | ctx ...
```

Design trace (after quest lands):

```text
session.1  # PreToolUse/PostToolUse hooks bind each session independently (self AND host repos):
           echo '{"conversationId":"conv-A","hookEventName":"PostToolUse","cwd":"<repo>","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 harness desk prepare --quest q-alpha"}}}' | bp3 q hooks
             -> writes <git-common-dir>/bp3/sessions/conv-A.json {"quest":"q-alpha","mode":"induct",...}
           echo '{"conversationId":"conv-B","hookEventName":"PostToolUse","cwd":"<repo>","toolCall":{"name":"edit_file","args":{"Path":"<repo>/docs/quests/q-beta/QUEST.red-ink.md"}}}' | bp3 q hooks
             -> writes <git-common-dir>/bp3/sessions/conv-B.json {"quest":"q-beta","mode":"red-ink","red_ink_path":"docs/quests/q-beta/QUEST.red-ink.md",...}
           # PostToolUse on `bp3 release q-alpha` clears conv-A.json without touching conv-B.json
           # SessionStart prunes session files with updated_ts older than 86400s
           dune test && ./test/hooks.sh && make check-full -> rc 0

session.2  # Parallel sessions in the SAME repo each see only their own quest:
           printf '{"session_id":"conv-A","cwd":"<repo>",...}' | NO_COLOR=1 ./scripts/agy-statusline
             -> bp3: q-alpha [████░░░░] 1/2 (50%) | ...
           printf '{"session_id":"conv-B","cwd":"<repo>",...}' | NO_COLOR=1 ./scripts/agy-statusline
             -> bp3: q-beta [red-ink] | ...
           printf '{"session_id":"conv-C","cwd":"<repo>",...}' | NO_COLOR=1 ./scripts/agy-statusline
             -> bp3: idle | ...   # even though q-beta/QUEST.red-ink.md exists on disk!
           rm <repo>/docs/quests/q-beta/QUEST.red-ink.md
           printf '{"session_id":"conv-B","cwd":"<repo>",...}' | NO_COLOR=1 ./scripts/agy-statusline
             -> bp3: idle | ...   # deleted working copy immediately unfreezes conv-B!
           ./test/agy-statusline.sh && make check-full -> rc 0
```

## Goal and why

Make the statusline trustworthy when running multiple terminals and central `~/.bp3/desks/` worktrees in parallel. With central desks, the main checkout stays permanently on `master`, so repo-global statusline heuristics (`quest/*` branch or globbing `QUEST.2b-reviewed.md`) break down completely: one abandoned file freezes every terminal, and parallel sessions stomp on each other. Binding each `session_id` to the quest it actually touches gives every terminal an accurate, zero-config HUD.

## Success picture

- Two `agy` / Claude sessions working on two different quests in the same repo simultaneously display their own distinct quests and progress bars.
- An unbound terminal shows `bp3: idle` even when another session is running `/red-ink` or an abandoned `QUEST.2b-reviewed.md` sits in `docs/quests/`.
- Deleting or adopting a `red-ink` working copy immediately clears `[red-ink]` on that session's statusline.
- `bp3 release <q>` clears that session's binding automatically, and stale session files (>24h) are garbage-collected on `SessionStart`.
- Works in both self (`bp3`) and host repos (e.g., `~/m/predictor`).

## Scope

| In | Out |
|---|---|
| Per-session quest binding in `src/quest/hooks.ml` (`<git-common-dir>/bp3/sessions/<sid>.json`) for self & host repos (`session.1`) | Storing statusline sessions in `bp3.sqlite` (keep `<2ms` direct file read from bash) |
| Stale 24h session file GC on `SessionStart` in `src/quest/hooks.ml` (`session.1`) | Changing `bp3` ledger formats or adding any new top-level CLI door |
| Session-scoped lookup + live `red_ink_path` existence check + `transcript_path` fallback in `scripts/agy-statusline` (`session.2`) | Automatic desk/worktree cleanup (separate quest `2026-11-25-desk-auto-cleanup`) |
| Unit + QCheck2 tests (`test/unit/test_hooks.ml`) and fixture tests (`test/hooks.sh`, `test/agy-statusline.sh`) | Editing `skills/*` (zero skill changes needed — automatic via hooks + statusline script) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Uses existing OCaml (`stdlib`, `unix`, `str`, `yojson`) and bash (`posix`, `git`, `jq`, `awk`) libraries on existing signed CLI surfaces (`bp3 q hooks` + `scripts/agy-statusline`). No edit to `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Q2 Storage (`CONTEXT.md:34-35`, checked 2026-11-19): *"Daemons that sync state draw complaints. bp3: no daemon."* Small atomic JSON files per session under `.git/bp3/sessions/` give lock-free parallel writes and sub-2ms statusline reads without a daemon or database lock.
  - Q3 Scaling (`CONTEXT.md:41`, checked 2026-11-19): *"People top out at about 3-6 sessions."* When running 3–6 parallel sessions against one repo, per-session status isolation is essential for human situational awareness.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (optional `/red-ink`) | owner |
| Promote & release (`goal_fin`: `/warden` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-session-scoped-statusline`) | owner |

## Nodes

### Milestone: session

| Node | TL;DR |
|---|---|
| [session.1 - hook-session-quest-binding](nodes/node-session-1-hook-session-quest-binding/NODE.md) | auto-bind `<git-common-dir>/bp3/sessions/<sid>.json` from `bp3 q hooks` (`desk prepare --quest`, `bp3 q <q>`, `red-ink` file edits, clear on `bp3 release <q>`, 24h GC on `SessionStart`) for both self & host repos + `test/unit/test_hooks.ml` & `test/hooks.sh` |
| [session.2 - agy-statusline-session-lookup](nodes/node-session-2-agy-statusline-session-lookup/NODE.md) | probe live `agy` statusLine stdin fields, switch `scripts/agy-statusline` to session-first lookup (with `transcript_path` fallback and live `red_ink_path` verification), kill repo-global `[red-ink]` hijack, and prove parallel isolation in `test/agy-statusline.sh` |

## Scorecard

| Row | Baseline (2026-11-25, `2ca58e09`) | Target | Read from |
|---|---|---|---|
| parallel sessions in one repo | share identical repo-global statusline | each session shows its own bound quest (or `bp3: idle`) | `test/agy-statusline.sh` |
| abandoned `QUEST.2b-reviewed.md` effect on unrelated terminals | freezes EVERY terminal at `[red-ink]` | **0 effect** on unbound or other-quest terminals | `test/agy-statusline.sh` |
| session binding in host repos (`docs/quests/`, no `bin/bp3`) | hooks skip `PreToolUse`/`PostToolUse` | binds `<git-common-dir>/bp3/sessions/<sid>.json` identically | `test/hooks.sh` |
| stale session cleanup | none | >24h session JSONs pruned on `SessionStart` | `test/hooks.sh` |

## Risks and red chair

Red chair of the plan AND the source prompt (Step 7.5):

- **Attack 1 (Critical — what if `agy`'s `statusLine` stdin payload omits `session_id` / `conversation_id`?):**
  - `agy` definitely sends `conversationId` to hooks (`src/quest/hooks.ml:346`), and Claude Code sends `session_id` + `transcript_path` to `statusLine`, but we have not captured a raw live `agy` `statusLine` stdin blob yet.
  - **Settled in `session.2`:** `session.2`'s first step runs a deterministic 1-command probe (temporary wrapper logging keys of one live `agy` statusLine payload, or inspecting `agy` binary/config) and records the observed keys in `LOG.md`. `scripts/agy-statusline` checks `.session_id // .conversation_id // .conversationId`, then extracts `<conv-id>` from `.transcript_path`, then checks `AGY_CONVERSATION_ID` / `CLAUDE_SESSION_ID`. If `agy` exposes zero session identifier on `statusLine` stdin, `session.2` parks per `induct` rules instead of shipping a silent no-op!
- **Attack 2 (Major — host repos blocked by `hooks.ml:367`'s `bin/bp3` check):**
  - Today `hooks.ml:367` checks `Sys.file_exists (Filename.concat gate_root "bin/bp3")`, so `PreToolUse`/`PostToolUse` immediately return `"not a bp3 repo"` in host repos (`~/m/predictor`), meaning host-repo sessions would never bind!
  - **Settled in `session.1`:** Decouple session quest binding from the `bin/bp3` self-mode check: run lightweight session binding whenever `gate_root` is a git repo containing `docs/quests/` (self OR host), while keeping the existing run-witness ledger logic gated exactly as before. Proved with an explicit host-repo test in `test/hooks.sh`.
- **Attack 3 (Major — malformed `session_id` escaping `<git-common-dir>/bp3/sessions/`):**
  - Untrusted `session_id` containing `../` or `/` could write outside `sessions/`.
  - **Settled in `session.1`:** Sanitize `session_id` with a pure allowlist (`[A-Za-z0-9._-]`, no leading `.`, no `..`, max 128 chars; reject invalid with no-op) proved by a QCheck2 property in `test/unit/test_hooks.ml`.
- **Attack 4 (Major — binding stale quest when an agent runs read-only `bp3 q r <other-quest>` or inspects another quest's `QUEST.md`):**
  - If a session working on Quest A runs `bp3 q r` (bare) or `bp3 warden` (which inspects other quests), it must NOT overwrite its binding!
  - **Settled in `session.1`:** Bind ONLY on explicit quest-intent actions: `bp3 harness desk prepare --quest <q>` / `bp3 worktree prepare --quest <q>`, mutating `bp3 q <q> ...` commands (`c`, `n ... e`, `u`, `d`, `dep`), explicit `bp3 q r <q>` (single quest slug, never bare `bp3 q r`), or editing/writing `docs/quests/<q>/QUEST.{red-ink,2b-reviewed}.md`. Never bind on `bp3 warden`, `bp3 q r` (bare), or `read_file`.
- **Attack 5 (Minor — `scripts/agy-statusline` invoking `bp3 q r` in a host repo where `$root/bin/bp3` does not exist):**
  - `scripts/agy-statusline:121-125` already falls back to `command -v bp3`, and `bp3` in host mode reads `git_common_dir` state branches directly. Verified in `test/agy-statusline.sh` with a host-mode fixture.

## Open questions

| # | Question | Owner | Default if untouched |
|---|---|---|---|
| 1 | Exact JSON key `agy` passes on `statusLine` stdin (`session_id` vs `conversation_id` vs `conversationId` vs `transcript_path`) | verified at start of `session.2` | Support all four in precedence order; park `session.2` if `agy` sends none |

## Node diagram

```text
Wave 1: session.1 (hook-session-quest-binding: hooks.ml <git-common-dir>/bp3/sessions/<sid>.json
                   bind/clear/24h-GC for self + host repos + test_hooks.ml + test/hooks.sh)
           │
Wave 2: session.2 (agy-statusline-session-lookup: probe agy statusLine keys, session-first lookup
                   in scripts/agy-statusline, live red_ink_path check, kill global hijack
                   + test/agy-statusline.sh)
```
