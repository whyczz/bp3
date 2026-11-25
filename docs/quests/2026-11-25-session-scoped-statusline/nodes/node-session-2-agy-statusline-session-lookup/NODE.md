---
date: 2026-11-25
quest: ../../QUEST.md
node: session.2
status: active
---

# session.2 - agy-statusline-session-lookup: switch `scripts/agy-statusline` to per-session lookup and kill global `[red-ink]` hijack

## TL;DR

Verify the exact session identifier key `agy` emits on `statusLine` stdin (recording the probe in `LOG.md`), then update `scripts/agy-statusline` to read `<canon(git_common_dir)>/bp3/sessions/<sid>.json` first (supporting `.session_id // .conversation_id // .conversationId`, `.transcript_path` extraction, and env fallback). When a session ID is present, show ONLY that session's bound quest (verifying `red_ink_path` still exists on disk for `[red-ink]`) or `quest/<slug>` branch, else `bp3: idle` — eliminating repo-global `[red-ink]` hijacking across parallel terminals.

## Acceptance gates

Observed today (2026-11-25, `2ca58e09`):

```text
$ rg -n 'session_id|conversation_id|bp3/sessions|git-common-dir' scripts/agy-statusline
# 0 matches
# Planting docs/quests/old-q/QUEST.2b-reviewed.md makes EVERY session payload output:
#   bp3: old-q [red-ink] | ctx ...
```

Design trace:

```text
# Repo has two quests (q-alpha, q-beta) AND an abandoned docs/quests/stale-q/QUEST.2b-reviewed.md on disk:
#   .git/bp3/sessions/sess-A.json -> {"quest":"q-alpha","mode":"induct",...}
#   .git/bp3/sessions/sess-B.json -> {"quest":"q-beta","mode":"red-ink","red_ink_path":"docs/quests/q-beta/QUEST.red-ink.md",...}
#   sess-C has NO session file.

$ printf '{"session_id":"sess-A","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20}}' "$proj" | NO_COLOR=1 ./scripts/agy-statusline
bp3: q-alpha [████░░░░] 1/2 (50%) | 2-second (handed_off c1) | 0s | ctx 200k/1.0M (20%)

$ printf '{"conversationId":"sess-B","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20}}' "$proj" | NO_COLOR=1 ./scripts/agy-statusline
bp3: q-beta [red-ink] | ctx 200k/1.0M (20%)

$ printf '{"session_id":"sess-C","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20}}' "$proj" | NO_COLOR=1 ./scripts/agy-statusline
bp3: idle | ctx 200k/1.0M (20%)

# Once q-beta/QUEST.red-ink.md is deleted (adopted), sess-B immediately drops [red-ink]:
$ rm "$proj/docs/quests/q-beta/QUEST.red-ink.md"
$ printf '{"conversationId":"sess-B","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20}}' "$proj" | NO_COLOR=1 ./scripts/agy-statusline
bp3: idle | ctx 200k/1.0M (20%)

$ ./test/agy-statusline.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: make scripts/agy-statusline resolve each terminal's own quest from <git-common-dir>/bp3/sessions/<sid>.json so parallel sessions never hijack each other and abandoned red-ink working copies never freeze the bar
prove by:
  - live probe of agy statusLine stdin JSON keys recorded in quest LOG.md (confirming session_id / conversation_id / transcript_path field)
  - test/agy-statusline.sh: (a) two parallel sessions sess-A and sess-B in the same repo display distinct quests simultaneously; (b) unbound sess-C displays `bp3: idle` even when an abandoned QUEST.2b-reviewed.md sits in docs/quests/; (c) red-ink session drops [red-ink] immediately when its working copy is deleted; (d) transcript_path fallback extracts session ID when session_id is absent; (e) quest/<slug> worktree branch fallback works; (f) legacy no-session payload preserves existing branch/active behavior and malformed stdin still exits 0
  - make check && make check-full (25/25 suites)
done when: parallel sessions are isolated, abandoned .2b-reviewed.md files cannot hijack unbound sessions, shellcheck passes, and all 25 suites pass
```

## Diagram

```text
stdin JSON -> jq extracts: cwd, session_id (or conversation_id / conversationId / transcript_path), context_window
  │
  ▼
common_dir = canon(git -C "$root" rev-parse --git-common-dir)
  │
  ├── sid present & valid?
  │     ├── YES:
  │     │     1. read "$common_dir/bp3/sessions/$sid.json"
  │     │          ├── mode == "red-ink" & red_ink_path exists -> show "<quest> [red-ink]"
  │     │          └── mode == "induct"  & quest not landed    -> show "<quest> [bar] ..."
  │     │     2. else if current branch is quest/<slug>        -> show "<slug> [bar] ..."
  │     │     3. else                                          -> show "bp3: idle | ctx ..."
  │     │                                                         (NEVER glob global red-ink!)
  │     └── NO (legacy session-less caller):
  │           1. current branch quest/<slug>
  │           2. active QUEST.md on current branch (or local red-ink)
  │           3. else "bp3: idle | ctx ..."
```

## Pseudocode

```python
# scripts/agy-statusline (bash + single jq pass)
j_cwd, j_sid, j_tx, j_pct, j_size, j_tin, j_tout = jq_extract(payload, [
    '.workspace.current_dir // .cwd // "."',
    '.session_id // .conversation_id // .conversationId // ""',
    '.transcript_path // ""',
    ...
])

sid = j_sid or extract_id_from_transcript_path(j_tx) or os.getenv("AGY_CONVERSATION_ID") or os.getenv("CLAUDE_SESSION_ID") or ""
if sid and not valid_sid(sid):
    sid = ""

common_dir = canon(git_common_dir(root))
quest, mode = "", ""

if sid:
    sfile = f"{common_dir}/bp3/sessions/{sid}.json"
    if exists(sfile):
        s_quest, s_mode, s_rpath = jq_read(sfile, ".quest", ".mode", ".red_ink_path")
        if s_mode == "red-ink":
            if s_rpath and exists(f"{root}/{s_rpath}"):
                quest, mode = s_quest, "red-ink"
        elif s_quest:
            quest, mode = s_quest, "induct"
    if not quest and branch.startswith("quest/"):
        quest = branch[len("quest/"):]
    # IMPORTANT: when sid is present and unbound, stay idle (do NOT glob docs/quests/*/QUEST.2b-reviewed.md!)
else:
    # Legacy session-less fallback (backwards compatible with existing fixtures)
    ...
```

## Tables

| Field | Value |
|---|---|
| Intent | render per-session quest status in `scripts/agy-statusline` and eliminate cross-terminal / abandoned-file hijacking |
| Lane | standard |
| Output | `scripts/agy-statusline`, `test/agy-statusline.sh` |
| Acceptance | fails today (`agy-statusline` ignores `session_id` and globs global `QUEST.2b-reviewed.md`); passes when `test/agy-statusline.sh` proves parallel session isolation and `make check-full` passes |
| Depends on | `session.1 - hook-session-quest-binding` |
| Must not touch | `src/*`, `skills/*`, `CONSTRAINTS.md`, `Makefile` |

## Prose

Note on `transcript_path` extraction: if a harness passes `"transcript_path": "/Users/.../.gemini/antigravity-cli/brain/<conv-id>/.system_generated/logs/transcript.jsonl"` or `"/Users/.../.claude/projects/.../<session-id>.jsonl"` without a top-level `session_id`, extracting `<conv-id>` (the directory segment immediately after `/brain/`) or `<session-id>` (basename without `.jsonl`) keeps session binding working seamlessly!

Note on `induct` sessions after a quest lands: if `<sid>.json` points to a quest whose `bp3 q r "$quest"` rollup reports `state == "landed"` (i.e. already promoted via `bp3 release`, perhaps from another terminal!), `scripts/agy-statusline` should treat it as idle (or skip showing a stale promoted quest) rather than showing an old finished quest forever.

## Tests

- **Fixture tests (`test/agy-statusline.sh`):**
  1. Parallel sessions `sess-A` (`q-alpha`, `induct`) and `sess-B` (`q-beta`, `red-ink`) in the same repo render their own distinct statuslines simultaneously.
  2. Unbound `sess-C` renders `bp3: idle` even with an abandoned `QUEST.2b-reviewed.md` present in `docs/quests/`.
  3. Deleting `q-beta/QUEST.red-ink.md` immediately drops `[red-ink]` for `sess-B` -> `bp3: idle`.
  4. `transcript_path` fallback (`.../brain/conv-A/.system_generated/logs/transcript.jsonl`) resolves `conv-A.json`.
  5. Existing legacy session-less tests (including multi-active `WARN`, non-bp3 dir, malformed JSON fail-open) continue to pass.
