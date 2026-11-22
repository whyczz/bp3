---
date: 2026-11-21
quest: ../../QUEST.md
node: reader.1
status: proposed
---

# reader.1 - pi-session: read a pi session into a cost record

## TL;DR

A new module, `Pi_tx`, parses one pi session file and returns the same
`Claude_tx.cost` record a Claude transcript gives (wall, tool calls,
context, four token counts, model). It also gives what the grade join
needs (session id, cwd, first user prompt and its time) and a
self-check. `Metrics.model_ok` learns a closed list of model families,
so `gpt-6.1-sol` is kept as itself rather than `other`.

## Acceptance gates

Observed today:

```text
$ ls src/quest/pi_tx.ml                          # No such file
$ Metrics.model_ok "gpt-6.1-sol"                 # false (claude-* only)
```

Design trace (unit, synthetic sessions, no real transcript in the repo):

```text
session: header {id "g1", cwd "/r"}, system, user "Grade nd at abc1234.", assistant (toolCall t1 bash, usage 100/10/0/0, total 110),
         toolResult t1, usage entry (cacheRead 50), assistant (text, usage 120/5/0/0, total 125)
Pi_tx.parse -> {session "g1"; cwd "/r"; first_prompt "Grade nd at abc1234."; first_ts; last_ts; tool calls [t1]; bad 0}
Pi_tx.cost  -> {tool_calls 1; tokens_in 220; tokens_out 15; tokens_cache_read 50; context_end 125; model "gpt-6.1-sol"}
self_checks -> true; total 111 instead of 110 -> false; toolResult t1 removed -> false; a count missing -> false
model_ok "gpt-6.1-sol", "claude-opus-5-5", "gemini-3-pro", "grok-5" -> true; "sk-proj-abc", "GPT-6", "gpt 6" -> false
```

```yaml
objective: bp3 reads a pi session's spend, and can tell when its own read doesn't add up
prove by:
  - test/unit/test_pi_tx.ml known cases above, plus a QCheck law
  - by hand, once: the probe session's totals against pi's /session readout (build notes)
  - make check-full
done when: the cases and the law pass, and model_ok accepts the four families and nothing else new
```

## Diagram

```text
<ts>_<id>.jsonl -> Pi_tx.parse -> tx {session, cwd, first_prompt, first_ts, last_ts, usages, tool_calls, tool_results, bad}
                                     |-> Pi_tx.cost        -> Claude_tx.cost record
                                     '-> Pi_tx.self_checks -> bool
```

## Pseudocode

```python
def parse(text):
    for line in lines(text):
        j = json_or_none(line)                       # junk lines: skipped_lines += 1, never read as 0
        if j.type == "session": session, cwd = j.id, j.cwd
        elif j.type == "message":
            m = j.message
            if m.role == "user" and not first_prompt: first_prompt, first_ts = text_of(m), j.timestamp
            if m.role == "assistant":
                usages.append((j.id, m.usage, m.model)); tool_calls += [b.id for b in m.content if b.type == "toolCall"]
            if m.role == "toolResult": tool_results.add(m.toolCallId); usages += [m.usage] if m.usage else []
        elif j.get("usage"): usages.append((j.id, j.usage, j.get("model")))   # usage, compaction, branch_summary
        if has_usage(j) and not complete(usage): bad += 1   # complete: all four counts, totalTokens = their sum

def cost(tx):   # same record as Claude_tx.cost
    last = last assistant usage
    return dict(wall_s=secs(tx.last_ts) - secs(tx.first_ts), tool_calls=len(tx.tool_calls),
                context_end=last.input + last.cacheRead + last.cacheWrite + last.output,
                tokens_*=sum over usages, model=family_or_other(last.model))

def self_checks(tx): return tx.bad == 0 and set(tx.tool_calls) <= tx.tool_results
```

## Tables

| Field | Value |
|---|---|
| Intent | one reader for pi sessions, shaped like the Claude one |
| Lane | standard |
| Output | `src/quest/pi_tx.ml`, `src/quest/metrics.ml` (`model_ok`), `test/unit/test_pi_tx.ml` |
| Acceptance | the module and the families above; fails today (no module, `model_ok` false) |
| Depends on | none |

| pi entry | Counted as |
|---|---|
| assistant message | usage, model, tool calls |
| `usage` entry (e.g. cache warm) | usage (pi counts it in session totals) |
| compaction / branch_summary with `usage` | usage |
| toolResult with `usage` (nested model work) | usage; its `toolCallId` pairs a call |
| system, model_change, thinking_level_change, custom | nothing |

## Prose

Each pi message is one line with an `id`, so there are no streamed
snapshots to collapse. That's simpler than Claude Code, where one
message spans several lines. Branches (`parentId` trees) still cost what
they cost, so every usage-bearing entry is counted, abandoned branches
included.

`reasoning` is already inside `output` (pi docs), so it's never added
again. `cacheWrite1h` is a subset of `cacheWrite`, so it's ignored.

The model families are a closed list, for the reason `model_ok` exists:
the model field must never carry free text or a key (QUEST.md R4 of
metric-collectors). `sk-proj-...` still reads as `other`.

Context end follows Claude's definition (the last assistant's prompt
size plus its output: input, cache read, cache write and output), so the two harnesses'
numbers mean the same thing.

## Tests

Known cases: the trace above, plus a junk line (counted in
`skipped_lines`, never read as 0) and an assistant line with no usage
(bad). Property-based: for any generated list of usage lines, the cost's
token sums equal the sums of the lines, and `self_checks` is false
whenever one total is off.

## Build notes (2026-11-21)

- `src/quest/pi_tx.ml`: `parse`, `self_checks`, `cost`. Usage-bearing
  entries are assistant messages, tool results with `usage`, and any
  other entry carrying `usage` (`usage`, compaction, branch summary). A
  usage that lacks a count, or whose `totalTokens` isn't the sum of the
  four, is `bad_usage`: left out and flagged, never read as 0.
- `context_end` is the last assistant's input + cacheRead + cacheWrite +
  output, which is Claude_tx.cost's meaning. The first draft of this
  record left out output; that's fixed above.
- `Metrics.model_ok` takes `model_families` (`claude-`, `gpt-`, `gemini-`,
  `grok-`). pi's local `mlx-local` models read as `other`.
- Real data, read-only:
  - the totals law holds on all 850 usage lines in ~/.pi (openai,
    mlx-local, compactions);
  - every `toolCall` has its `toolResult` except one interrupted call in
    one old session, which the self-check rightly fails.
- Oracle, by hand. pi's `/session` prints nothing in print mode, but RPC
  mode's `get_session_stats` gives pi's own totals with no model call
  and leaves the file unchanged. Both checks used the rule `Pi_tx`
  implements:
  - the probe session matches exactly (5046 / 5 / 0 / 0, 5051);
  - bp3's largest pi session (866 lines, with compactions) matches
    exactly: 298 assistant messages, 517 tool calls, input 1,589,336,
    output 296,080, cacheRead 33,388,032, total 35,273,448.
  The comparison ran jq over the files, not the OCaml reader; the unit
  tests tie the reader to the rule.
- This finding bears on Open question 3: `get_session_stats` is a free,
  independent oracle a scrape could call.
