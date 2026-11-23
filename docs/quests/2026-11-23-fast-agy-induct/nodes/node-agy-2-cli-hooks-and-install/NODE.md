---
date: 2026-11-23
quest: ../../QUEST.md
node: agy.2
status: proposed
---

# agy.2 - cli-hooks-and-install: bin/bp3 --harness=agy, camelCase hooks, CONSTRAINTS.md sign-off

## TL;DR

Add `agy` as a supported harness in `bin/bp3` (`harness_target` -> `.agents/skills`, `--harness=all`, emit `.agents/hooks.json` in `agy`'s named-group schema), teach `src/quest/hooks.ml` to parse `agy`'s camelCase hook payload alongside Claude/Muse snake_case, and record the owner's `CONSTRAINTS.md` sign-off adding `agy` to the driven harness CLIs line.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 skills install --harness=agy
unknown harness: agy
$ ls .agents/hooks.json
ls: .agents/hooks.json: No such file or directory
```

Design trace:

```text
$ BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=agy
  - installs skills -> .agents/skills/<skill>/SKILL.md (agy)
  - writes .agents/hooks.json in agy's named-group schema:
      {"bp3": {"SessionStart": [{"type":"command","command":"./bin/bp3 q hooks || true"}],
               "PreToolUse":   [{"matcher":"run_command","hooks":[...]}],
               "PostToolUse":  [{"matcher":"run_command","hooks":[...]}],
               "Stop":         [{"type":"command","command":"./bin/bp3 q hooks || true"}]}}
  - in host mode, hook command is "bp3 q hooks || true"

$ printf '{"conversationId":"conv-1","hookEventName":"PostToolUse","toolCall":{"name":"run_command","args":{"CommandLine":"make check"}}}\n' | ./bin/bp3 q hooks
  - exit 0 (fail-open), prints `{}` (valid JSON expected by agy hooks) or records event when bound to a Run
```

```yaml
objective: install skills and agy-formatted hooks via bp3 skills install --harness=agy and parse agy camelCase hook payloads in bp3 q hooks
prove by:
  - test/skills.sh: --harness=agy installs .agents/skills/* and valid .agents/hooks.json (both self and host mode); --harness=all includes agy
  - test/hooks.sh: camelCase agy payloads (SessionStart, PreToolUse, PostToolUse with toolCall.args.CommandLine, Stop) parse and fail-open with exit 0 and valid JSON stdout
  - test/check-constraints.sh and CONSTRAINTS.md sign-off log row
  - make check-full
done when: skills.sh, hooks.sh, check-constraints.sh, and make check-full pass
```

## Diagram

```text
bin/bp3 skills install --harness=agy
   ├─ .agents/skills/<skill>/SKILL.md   (same dir as codex/muse)
   └─ .agents/hooks.json                (agy named-group schema, fail-open `|| true`)
                                              │
                                              ▼
                                      bp3 q hooks (stdin)
                                    ┌─────────┴─────────┐
                           snake_case (Claude/Muse)  camelCase (agy)
                           session_id                conversationId
                           hook_event_name           hookEventName
                           tool_input.command        toolCall.args.CommandLine
                                    └─────────┬─────────┘
                                              ▼
                                 normalized event -> ledger (exit 0)
```

## Pseudocode

```python
# src/quest/hooks.ml normalization helpers
def session_id_of(j):
    return member_str(j, "session_id") or member_str(j, "conversationId")

def event_name_of(j):
    return member_str(j, "hook_event_name") or member_str(j, "hookEventName")

def command_of(j):
    # Claude/Muse: tool_input.command
    # agy:         toolCall.args.CommandLine
    return (
        nested_str(j, ["tool_input", "command"])
        or nested_str(j, ["toolCall", "args", "CommandLine"])
    )
```

## Tables

| Field | Value |
|---|---|
| Intent | make `bp3 skills install --harness=agy` and `bp3 q hooks` work natively with `agy` |
| Lane | standard |
| Output | `bin/bp3`, `src/quest/hooks.ml`, `CONSTRAINTS.md` (with owner-words sign-off row), `completions/_bp3`, `completions/bp3.bash`, `test/skills.sh`, `test/hooks.sh`, `test/completion.sh` |
| Acceptance | fails today (`unknown harness: agy`, no `.agents/hooks.json`, `hooks.ml` ignores camelCase); passes when tests + `make check-full` pass |
| Depends on | none |
| Must not touch | `scripts/red-first`, `scripts/receipt`, `src/quest/brief.ml`, `src/quest/tx.ml`, `src/quest/agy_tx.ml`, `src/quest/metrics*.ml`, `skills/*` |

## Prose

Critical `agy` hook schema details (verified from `agy-customizations/docs/hooks.md`):
- **Top-level key is a hook name** (`"bp3": { ... }`), NOT `"hooks": { ... }`.
- **Event structure differs by event:** `SessionStart` and `Stop` are **flat** arrays of handler objects (`[{"type":"command","command":"..."}]`), whereas `PreToolUse` and `PostToolUse` are **grouped** with `matcher` + `hooks` (`[{"matcher":"run_command","hooks":[...]}]`).
- **Working directory:** `agy` runs hooks with cwd = directory containing `hooks.json` (`.agents/`), while the payload carries `"cwd": "/path/to/workspace"`. Therefore the `self`-mode hook command in `.agents/hooks.json` must invoke `../bin/bp3 q hooks || true` (or check `[ -x ../bin/bp3 ]`) rather than `./bin/bp3` — good catch from reading `hooks.md:131`!
- **Output contract:** `agy` `PreToolUse` expects `{"decision":"allow"}` on stdout (empty or non-PreToolUse JSON could surprise `agy`!); `PostToolUse` expects `{}`. So when `hooks.ml` detects an `agy` camelCase payload (`conversationId` present), emit `{"decision":"allow"}` for `PreToolUse` and `{}` for all other `agy` events so hooks are 100% fail-open and never block `run_command`!
- **`CONSTRAINTS.md` rule:** this node's commit must quote the owner's exact approval words in a dated row of `CONSTRAINTS.md`'s Sign-off log when adding `agy` to line 54.
