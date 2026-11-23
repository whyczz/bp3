---
date: 2026-11-23
quest: ../../QUEST.md
node: agy.1
status: proposed
---

# agy.1 - tx-core-and-scrape: shared Tx module, Agy_tx transcript reader, Store.identity fix

## TL;DR

Extract harness-neutral transcript types, tool-event traces (`tool_event`: name, `cmd_head`, `is_error`, span, step/line), and interval math out of `Claude_tx` into `src/quest/tx.ml`, implement `src/quest/agy_tx.ml` to parse `agy` `transcript.jsonl` files (both grader subagents and main author sessions), wire `~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl` into `src/quest/metrics_io.ml` (recording `tool_errors` and `turns` in `metrics.jsonl` and exposing a reusable `joined_traces` reader for Warden Layer 2), and add `agy`, `claude`, and `pi` to `Store.identity`'s `BP3_HARNESS` allowlist.

## Acceptance gates

Observed today:

```text
$ BP3_HARNESS=agy ./bin/bp3 q r 2026-11-22-induct-inline-as-default-measure-author
{"ok":false,"error":{"code":"E_IDENTITY","facts":{"harness":"agy"},...}}
$ ls src/quest/tx.ml src/quest/agy_tx.ml
ls: src/quest/tx.ml: No such file or directory
ls: src/quest/agy_tx.ml: No such file or directory
```

Design trace:

```text
$ BP3_HARNESS=agy ./bin/bp3 q r <quest>        # ok:true, no E_IDENTITY (claude, pi also accepted)
$ bp3 q <quest> metrics scrape --agy-dir <fixture-brain-dir>
  - grader transcript with first USER_INPUT "Grade nd at abc1234 ..." -> grade.* written, self_checked=1, run="agy:<conv-id>", model="gemini-4-neon-medium"
  - author transcript with PLANNER_RESPONSE tool_calls casting `bp3 q <q> n <n> e handoff --commit <sha>` -> author.* written (wall_s, active_s, tool_s, tokens_in, tokens_out, tokens_cache_read, tool_calls), authored=1
  - truncated USER_INPUT/tool step with truncated_fields -> falls back to sibling transcript_full.jsonl
  - missing token count on PLANNER_RESPONSE -> bad_usage > 0 -> mismatched / author_bad_usage, nothing written
```

```yaml
objective: measure agy grader and author runs in metrics scrape through a clean harness-neutral Tx abstraction (preserving compact tool_events for Warden Layer 2), and allow agy/claude/pi in BP3_HARNESS
prove by:
  - test/unit/test_agy_tx.ml: parses real-shaped agy transcript.jsonl (USER_INPUT, PLANNER_RESPONSE, GENERIC), computes wall_s/active_s/tool_s/tokens/tool_calls/tool_errors/turns and tool_events (name, cmd_head, is_error, step), handles truncated_fields fallback, rejects missing token counts (bad_usage > 0)
  - test/unit/test_metrics.ml and test/metrics.sh: existing Claude + pi tests unchanged and green; new --agy-dir fixture tests both agy grade and agy author windows (including tool_errors and turns)
  - test/g.sh: BP3_HARNESS=agy, claude, pi accepted; invalid value still E_IDENTITY
  - make check-full
done when: all unit and fixture tests pass, pi_tx.ml no longer imports Claude_tx, and Metrics_io exposes joined_traces for Warden Layer 2
```

## Diagram

```text
               ┌───────────────┐
               │ src/quest/tx  │  (usage, cost, tool_event, turns, tool_errors,
               └───────┬───────┘   seconds, merge/measure/inter, paired, join)
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
    Claude_tx        Pi_tx        Agy_tx
  (~/.claude/)    (~/.pi/agent/) (~/.gemini/antigravity-cli/brain/)
         └─────────────┼─────────────┘
                       ▼
               src/quest/metrics_io.ml
         ├─► metrics.jsonl (wall, active, tool_s, tokens, tool_calls, tool_errors, turns)
         └─► joined_traces (reused by Warden Layer 2 session-trace plugs)
```

## Pseudocode

```python
# agy transcript.jsonl observed fields:
#   USER_INPUT:       {step_index, type:"USER_INPUT", created_at, content, truncated_fields?}
#   PLANNER_RESPONSE: {step_index, type:"PLANNER_RESPONSE", created_at, model,
#                      input_tokens, cache_read_tokens, output_tokens, tool_calls:[{name,args}]}
#   GENERIC:          {step_index, type:"GENERIC", status, created_at, content, truncated_fields?}

def parse_agy(path):
    lines = read_lines(path)
    full_lines = None  # lazy load sibling transcript_full.jsonl only if truncated_fields present
    for idx, j in enumerate(lines):
        if has_truncated(j):
            j = read_full_line(path, idx, full_lines) or j
        match j["type"]:
            case "USER_INPUT":
                if first_prompt is None: first_prompt = j["content"]
            case "PLANNER_RESPONSE":
                u = usage(j["input_tokens"], j["output_tokens"], j["cache_read_tokens"], 0)
                # if any of the 3 counts missing -> bad_usage += 1
                record_msg(j["created_at"], j["model"], u, has_tools=bool(j.get("tool_calls")))
                record_tool_calls(j["created_at"], j.get("tool_calls", []))
            case "GENERIC":
                record_tool_end(j["created_at"])  # pairs with preceding PLANNER_RESPONSE tool batch
```

## Tables

| Field | Value |
|---|---|
| Intent | make `agy` metrics scraping work cleanly and remove `Pi_tx`'s inverted dependency on `Claude_tx` |
| Lane | standard |
| Output | `src/quest/tx.ml` (new), `src/quest/agy_tx.ml` (new), `src/quest/claude_tx.ml`, `src/quest/pi_tx.ml`, `src/quest/metrics_io.ml`, `src/quest/main.ml` (`--agy-dir` flag on `metrics scrape`), `src/quest/store.ml` (`BP3_HARNESS` allowlist), `test/unit/test_agy_tx.ml`, `test/unit/dune`, `test/metrics.sh`, `test/g.sh` |
| Acceptance | fails today (`BP3_HARNESS=agy` -> `E_IDENTITY`, no `Agy_tx`); passes when unit + fixture tests pass |
| Depends on | none |
| Must not touch | `scripts/red-first`, `scripts/receipt`, `bin/bp3`, `src/quest/hooks.ml`, `src/quest/brief.ml`, `skills/*`, `CONSTRAINTS.md` |

## Prose

Inspecting a live `agy` `transcript.jsonl` on 2026-11-23 confirmed the exact field names: `step_index`, `type` (`USER_INPUT`, `PLANNER_RESPONSE`, `GENERIC`), `created_at` (ISO-8601 UTC), `model`, `input_tokens`, `cache_read_tokens`, `output_tokens`, `tool_calls`.

Edge cases:
- **Filtering brain dirs to this repo:** unlike Claude/Pi, `agy`'s `brain/<conv-id>/` dirs are UUID-keyed, not cwd-slug-keyed. Filter candidates cheaply: only parse transcripts whose mtime >= the quest's earliest ledger timestamp (or whose text mentions the quest slug / node id), keeping `metrics scrape` fast even with hundreds of past conversations.
- **Active time for `agy` authors:** a `PLANNER_RESPONSE` with `tool_calls = []` (or absent) is the `agy` equivalent of Claude's `end_turn` — gaps starting at a tool-less `PLANNER_RESPONSE` count as idle (not `active_s`).
- **`truncated_fields`:** when `transcript.jsonl` truncates a large `USER_INPUT` (such as a multi-KB `brief`) or `run_command` output, `Agy_tx` reads that exact line from `transcript_full.jsonl` so `Brief.is_verbatim` and `casts_handoff` never false-fail on truncation.
- **`cache_write`:** `agy` reports `input_tokens`, `output_tokens`, `cache_read_tokens` (no separate cache-write field); set `cache_write = 0` cleanly.
- **`model_ok`:** verify `Metrics.model_ok` accepts `agy` model strings like `gemini-4-neon-medium` / `gemini-4-neon-xhigh` / `gemini-4-hydrogen` (lowercase alphanumeric + hyphens + dots).
