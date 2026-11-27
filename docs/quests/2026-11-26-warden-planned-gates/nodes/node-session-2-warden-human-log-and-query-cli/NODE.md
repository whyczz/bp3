---
node: session.2
slug: warden-human-log-and-query-cli
kind: code
lane: standard
status: proposed
depends_on:
  - gate.1 - warden-human-gate-hygiene
  - session.1 - quest-session-log-and-turn-parser
---

# session.2 - warden-human-log-and-query-cli

TL;DR
Expose `bp3 warden human-log (<quest> | --session <id|latest>) [--phase ...] [--limit 200]`, `bp3 warden query <session-id|latest> --around <step> [--window 5]`, and `bp3 warden --session <id|latest>` in `src/quest/{names,main}.ml` + `src/warden/{warden,warden_io}.ml`, add `human_turns_count` to default `bp3 warden` JSON (O(1) via durable hook log + joined traces), wire completions & help text, and cover with unit, QCheck2, and CLI fixture tests.

## Acceptance gates

Design trace:

```text
# 1. Quest-wide human-log (unions durable quest-sessions/<q>.jsonl + fast retroactive scan fallback)
$ bp3 warden human-log demoq --format json
{"ok":true,"scope":"quest","quest":"demoq","sessions":["conv-1"],"interactions":[{"phase":"red-ink","session_id":"conv-1","harness":"agy","step":42,"ts":"...","source":"ask_question","agent_asked":"...","human_said":"A1: ...","nearby_edges":[]}],"truncated":false}

# 2. Standalone post-/red-ink audit via --session latest
$ bp3 warden human-log --session latest --format table
$ bp3 warden --session latest --format json
{"ok":true,"scope":"session","quests":[],"sessions_scanned":1,"planned_gates":[],"human_turns_count":6,"findings":[...]}

# 3. Drill-down query around one interesting step
$ bp3 warden query latest --around 42 --window 5 --format json
{"ok":true,"session_id":"conv-1","harness":"agy","around":42,"window":5,"steps":[...]}

# 4. Refusals
$ bp3 warden query latest                          -> E_USAGE (exit 2: --around is required)
$ bp3 warden human-log demoq --session latest      -> E_USAGE (exit 2: conflicting scope)
$ bp3 warden query nonexistent-sid --around 1      -> E_NOT_FOUND (exit 1)
```

Runnable goal block:
- **objective:** Deliver the full `bp3 warden human-log`, `bp3 warden query`, and `bp3 warden --session <id|latest>` CLI surface with fast session discovery and completions.
- **prove by:** Unit + QCheck2 tests in `test/unit/test_warden.ml` and CLI/completion suites in `test/warden.sh` and `test/completion.sh`.
- **done when:** `make check-full` passes with all subcommand happy paths, phase filters, limit truncations, standalone `--session latest`, refusals, and shell completions green.

## Diagram

```text
bp3 warden <argv>
  |-- "human-log" :: rest -> parse (<quest> | --session <id|latest>) [--phase] [--limit 200] [--format]
  |                            |-- <quest>: quest-sessions/<q>.jsonl U retroactive scan (Tx.contains prefilter)
  |                            |-- --session: find by exact id or latest mtime across agy/claude/pi dirs
  |                            v
  |                          Warden.build_human_log (dedupe, assign_phase, filter phase, apply limit)
  |-- "query" :: rest     -> parse <session-id|latest> --around <step> [--window 5] [--format]
  |                            v
  |                          Warden_io.query_session -> bounded QueryStep list
  +-- default             -> [<quest> | --session <id|latest>] [--last|--all] [--no-sessions] [--format]
                               |-- --session: scope="session", L2 tool_retry_loop + context_bloat only
                               +-- <quest>/repo: full L1+L2 + planned_gates[] + human_turns_count (O(1) log only)
```

## Pseudocode

```python
def discover_quest_sessions(quest: str, *, allow_retro_scan: bool) -> list[SessionRef]:
    # Primary: O(1) read of <git-common-dir>/bp3/quest-sessions/<quest>.jsonl
    refs = read_quest_session_log(quest)
    if allow_retro_scan:
        # Fast substring prefilter (Tx.contains) before JSON parse on agy/claude/pi files
        needle_doc = f"docs/quests/{quest}/"
        needle_cmd = f"bp3 q {quest}"
        refs = union_dedupe_by_sid(refs, scan_transcripts_matching(needle_doc, needle_cmd))
    return refs

def assign_phase(turn_ts: float, session_events: list[QuestSessionEvent], fallback_phase: str) -> str:
    # Latest QuestSessionEvent with ev.ts <= turn_ts wins; else fallback_phase ("standalone" or "init")
    ...
```

## Fields

| Field | Value |
|---|---|
| Intent | Wire `human-log`, `query`, and `--session <id\|latest>` into `bp3 warden` CLI, I/O discovery, and completions |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/quest/{names,main}.ml`, `src/warden/{warden,warden_io}.ml`, `bin/bp3`, `completions/{_bp3,bp3.bash}`, `test/unit/test_warden.ml`, `test/warden.sh`, `test/completion.sh` |
| Acceptance | Fails today (`bp3 warden human-log` and `bp3 warden query` fail with `E_USAGE`); passes when all subcommands, flags, refusals, and completions work end-to-end |
| Depends on | `gate.1 - warden-human-gate-hygiene`, `session.1 - quest-session-log-and-turn-parser` |

## Prose & edge cases

- **Performance guard (Closing Red Chair #3):** Default `bp3 warden [<quest>]` computes `human_turns_count` ONLY from sessions already listed in `.git/bp3/quest-sessions/<q>.jsonl` (plus already-joined traces) — NEVER running the retroactive full-dir scan on default `bp3 warden`. Retroactive scan runs ONLY on `bp3 warden human-log <quest>`, pre-filtering file bytes with `Tx.contains` before JSON parsing.
- **Standalone `--session <id|latest>` plug scope (Closing Red Chair #2):** When `bp3 warden --session <id|latest>` runs without a quest ledger, `scope = "session"`, `quests = []`, `planned_gates = []`, Layer-1 plugs are skipped, and Layer-2 runs only `tool_retry_loop` + `context_bloat` (never `human_steer` or `full_gate_in_author`).
- **Reserved subcommand names:** `human-log` and `query` are matched before `<quest>` dispatch in `Main.do_warden` and added to `Names` so completions and help stay single-source-of-truth.
- **`--session latest`:** Picks the single transcript file with highest `st_mtime` across configured `agy`/`claude`/`pi` dirs; returns `E_NOT_FOUND` if zero transcripts exist; always echoes the concrete resolved `session_id` in output.
- **Tests:**
  - *Known cases:* `human-log <quest>` via durable hook log, `human-log <quest>` via retroactive scan when hook log is absent, `--phase red-ink` filter, `--limit 2` sets `truncated: true`, `--session latest` resolution, `query --around` json & table, `bp3 warden --session latest` skips `human_steer` while catching `tool_retry_loop`, all `E_USAGE` & `E_NOT_FOUND` refusals, `completions/_bp3` & `completions/bp3.bash`.
  - *Property-based (QCheck2):* Phase assignment monotonicity + dedupe-by-`(session_id, step)` idempotency across shuffled/duplicate session event lists.
