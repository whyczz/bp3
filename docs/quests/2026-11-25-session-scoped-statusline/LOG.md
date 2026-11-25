# Run log — 2026-11-25-session-scoped-statusline

Quest: [QUEST.md](QUEST.md)  
Branch: `quest/2026-11-25-session-scoped-statusline`  
Mode: `/induct-yolo` (no-human rails)

## Nodes

| Node | Wave | Lane | Status | Cycle | Commit | Notes |
|---|---|---|---|---|---|---|
| `node-session-1-hook-session-quest-binding` | 1 | standard | landed (`node_fin`) | 1 | `2f39cb5c` | c1 `ship` (0 findings, 2 minor follow-ups, 25/25, `red-first: red (ocaml)`) |
| `node-session-2-agy-statusline-session-lookup` | 2 | standard | landed (`node_fin`) | 1 | `d6a0688b` | c1 `ship` (0 findings, 2 minor follow-ups, 25/25, `red-first: red (agy-statusline)`) |

## Build notes & lessons

- **2026-11-25**: Quest initialized on `master` `ba2bd5db` (`v0.6.0`), authoring directly in central desk `~/.bp3/desks/bp3-3951d199/quests/2026-11-25-session-scoped-statusline`.
- **`session.1` relative `--git-common-dir` lesson**: `git -C "$host" rev-parse --git-common-dir` returns relative `.git` (relative to `$host`, not the caller's cwd), so callers resolving it in bash must `cd "$host" && cd "$(git rev-parse --git-common-dir)" && pwd -P`.
- **`session.2` `agy` `statusLine` stdin payload probe (2026-11-25)**: Verified against official Antigravity CLI (`agy`) documentation (`antigravity.google/docs/cli/reference.md`): `agy` pipes JSON to `statusLine` stdin containing top-level fields `cwd`, `session_id` (kept for compatibility; matches `conversation_id`), `conversation_id`, `conversation_title`, `transcript_path`, `model`, `agent_state`, `context_window`, `vcs`, `sandbox`, `terminal_width`, `artifact_count`, `subagents`, `task_count`, `email`. Open question #1 is settled: `scripts/agy-statusline` resolves `.session_id // .conversation_id // .conversationId`, falling back to `transcript_path` extraction (`.../brain/<conv-id>/...` or `.../<sid>.jsonl`) and `AGY_CONVERSATION_ID` / `CLAUDE_SESSION_ID`.
- **`session.2` bash `IFS=$'\t'` lesson**: Because tab is whitespace in bash, `IFS=$'\t' read` collapses consecutive tabs from empty `@tsv` fields; emitting `"__NONE__"` sentinels from `jq` keeps all fields aligned reliably.
- **2026-11-25**: Both nodes reached `node_fin` (`rollup: landed`, `fin: goal_fin`); 2/2 cold grades verbatim (`brief_verbatim: 2, brief_edited: 0`), zero open grade desks. Ready for owner `/warden` and `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-session-scoped-statusline`.
