---
node: session.1
slug: quest-session-log-and-turn-parser
kind: code
lane: standard
status: proposed
depends_on: []
---

# session.1 - quest-session-log-and-turn-parser

TL;DR
Persist a durable machine-local quest-session log (`.git/bp3/quest-sessions/<quest>.jsonl`) in `src/quest/hooks.ml` (never committed, no 24h TTL), and add pure full-session `HumanTurn` (`USER_INPUT` + paired `ask_question`/`AskUserQuestion` Q&A) and `QueryStep` (`[step - window .. step + window]`) parsers to `src/quest/{tx,agy_tx,claude_tx,pi_tx}.ml` with strict excerpt bounds.

## Acceptance gates

Design trace:

```text
# 1. Hook logs durable quest-session phases without duplicate consecutive lines
PostToolUse(edit QUEST.red-ink.md, sid="conv-1") -> appends {"sid":"conv-1","harness":"agy","phase":"red-ink","ts":...} to .git/bp3/quest-sessions/<q>.jsonl
PostToolUse(edit QUEST.red-ink.md, sid="conv-1") -> deduped (no duplicate line when (sid, phase) unchanged)
PostToolUse(bp3 q <q> n n1 e handoff, sid="conv-1") -> appends {"sid":"conv-1","harness":"agy","phase":"induct","ts":...}

# 2. Pure transcript interaction & query extraction (agy, claude, pi)
Agy_tx.parse_interactions(text, ?full_text) -> [HumanTurn(step=1571, source="user_input", ...), HumanTurn(step=1604, source="ask_question", agent_asked="...", human_said="A1: ...")]
Agy_tx.query_window(text, ?full_text, ~around=1571, ~window=5) -> bounded steps [1566..1576], each text <= 2000 chars
```

Runnable goal block:
- **objective:** Record every session touching a quest across its full lifecycle and extract bounded human interactions and step drill-down windows purely in OCaml.
- **prove by:** Unit + QCheck2 tests in `test/unit/test_hooks.ml` and `test/unit/test_agy_tx.ml` / `test/unit/test_tx.ml`, plus hook fixture tests in `test/hooks.sh`.
- **done when:** `make check-full` passes with durable hook logging, `USER_INPUT` + `ask_question` pairing, `transcript_full.jsonl` truncation resolution, and QCheck2 excerpt/window bounds laws green.

## Diagram

```text
PostToolUse hook payload ---> Hooks.extract_quest_phase
                                  |-- QUEST.red-ink.md / QUEST.2b-reviewed.md -> "red-ink"
                                  |-- bp3 warden / bp3 release                -> "fin"
                                  |-- bp3 q <q> ...                           -> "induct"
                                  |-- QUEST.md / NODE.md                      -> "init"
                                  v
                       <git-common-dir>/bp3/quest-sessions/<q>.jsonl (deduped consecutive (sid,phase))

Transcript JSONL ---> Agy_tx / Claude_tx / Pi_tx (pure)
                        |-- parse_interactions -> Tx.human_turn list (agent_asked<=300, human_said<=1000)
                        +-- query_window       -> Tx.query_step list ([around-w..around+w], text<=2000)
```

## Pseudocode

```python
@dataclass(frozen=True)
class HumanTurn:
    step: int
    ts: float
    iso_ts: str
    source: Literal["user_input", "ask_question"]
    agent_asked: str        # truncated <= 300 chars
    human_said: str         # truncated <= 1000 chars (strips Created At / Completed At headers)
    nearby_edges: list[str] # bp3 q edge commands seen near this turn

@dataclass(frozen=True)
class QueryStep:
    step: int
    ts: str
    role: Literal["user", "assistant", "tool_call", "tool_result", "system"]
    text: str               # truncated <= 2000 chars

def clip(s: str, max_chars: int) -> str:
    s = collapse_whitespace(s.strip())
    return s if len(s) <= max_chars else s[: max_chars - 3] + "..."
```

## Fields

| Field | Value |
|---|---|
| Intent | Add durable quest-session hook log and pure full-session human-turn & query-window parsers |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/quest/{hooks,tx,agy_tx,claude_tx,pi_tx}.ml`, `test/unit/{test_hooks,test_agy_tx,test_claude_tx,test_pi_tx}.ml`, `test/hooks.sh` |
| Acceptance | Fails today (no `quest-sessions/` log in `hooks.ml`; `*_tx.ml` discard human text and have no `query_window`); passes when hook log + parsers + QCheck2 bounds pass |
| Depends on | none |

## Prose & edge cases

- **No TTL expiry on `quest-sessions/`:** Unlike `.git/bp3/sessions/<sid>.json` (which expires after 24h for statusline hygiene), `.git/bp3/quest-sessions/<quest>.jsonl` is NEVER pruned by `SessionStart` TTL so multi-day quests remain auditable from `init` to `fin`.
- **Safe path sanitization:** Reuse `Hooks.sanitize_session_id` and quest slug validation so malformed IDs or `../` payloads never write outside `<git-common-dir>/bp3/quest-sessions/`.
- **Pairing `ask_question` / `AskUserQuestion`:**
  - In `agy_tx.ml`: pair `PLANNER_RESPONSE` tool call `name = "ask_question"` with its matching `GENERIC` result via existing FIFO `pending` queue; extract the question strings for `agent_asked` and strip `Created At:` / `Completed At:` lines from the `GENERIC` `content` for `human_said`.
  - Reuse `Agy_tx`'s existing `truncated_fields` -> `transcript_full.jsonl` resolution so long `USER_INPUT` or `ask_question` replies are never silently truncated before `clip`.
  - In `claude_tx.ml`: capture human `user` text messages (`is_human_user`) plus `AskUserQuestion` tool_use/tool_result pairs when present.
  - In `pi_tx.ml`: capture human user messages and step window lines cleanly.
- **Skip noise:** Ignore empty messages and `/compact` commands (matching existing `agy_tx.ml:117`).
- **Tests:**
  - *Known cases:* hook appends `init`/`red-ink`/`induct`/`fin`, skips duplicate consecutive `(sid, phase)`, rejects bad `sid`; `agy_tx` parses `USER_INPUT` + paired `ask_question` + `transcript_full.jsonl` fallback + `query_window` boundaries (start/middle/end of file); `claude_tx` and `pi_tx` parse human turns + `query_window`.
  - *Property-based (QCheck2):* For arbitrary strings and `window >= 0`, `clip` always returns `String.length <= max_chars`, and every step returned by `query_window ~around ~window` satisfies `around - window <= step <= around + window` with `String.length text <= 2000`.
