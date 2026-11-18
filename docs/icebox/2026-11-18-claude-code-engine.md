---
status: frozen
date: 2026-11-18
promoted: null
---

# Try Claude Code tasks and agents as a bp3 engine

## Context

Frozen 2026-11-18. Owner, verbatim: "how do try out tasks,
agents in claude code?"

bp3 runs two engines today: `muse-code` and `pi`
(`src/graph/harness.ml` rejects any other engine value). Claude
Code is only a render target: `bp3 init --harness=claude`
writes `.claude/skills/` and merges hooks into
`.claude/settings.json`; `PostLLMCall` was dropped there on
2026-11-18 because Claude Code has no such event. The neighbor
entries are the Muse workflow dossier
(`docs/dossiers/muse-workflows-hooks.md`) and omp tasks
([2026-11-15-explore-omp-tasks.md](2026-11-15-explore-omp-tasks.md)).

Claude Code primitives that look like bp3 engines. These were
observed in a 2026-11-18 session's tool list, not from the docs;
re-verify at thaw.

| Claude Code | Closest bp3/Muse twin |
|---|---|
| Agent tool: typed subagents (`.claude/agents/*.md`: model, tools), background, `isolation: worktree`, SendMessage to continue | Muse `agent()`, omp task |
| Workflow tool: JS `agent()/parallel()/pipeline()/phase()`, resume by run id, needs explicit user opt-in | Muse workflow |
| Headless `claude -p --output-format stream-json` | pi pane (stream = tape) |
| Hooks `SubagentStart` / `SubagentStop`, `PreToolUse`, ... | `bp3 g hooks` bindings |

## Sketch

Trials before code. Each one is timed and token-counted, with
`toy-solo-clean` as the fixture graph.

1. **Agent tool.** Conduct with `bp3g` from Claude Code; the
   author child is a subagent with `isolation: worktree`.
   Record the `SubagentStart`/`SubagentStop` payloads and whether
   `bp3 g hooks` binds the child to its Run (binding is witnessed
   via `BP3_RUN_ID=...` in the tool command; a subagent gets no
   env).
2. **Workflow tool.** Port the muse-code workflow engine's script
   shape: one `agent()` per node, with a schema'd return.
3. **Headless pane.** `claude -p` as a pi-style pane, with
   stream-json as the tape. Can `bp3 harness backtest` scrape
   usage from it?

Only after the trials: `claude-code` joins the engine allowlist
with a tape shape and a usage scraper. Deliberately not: no
engine code before trial evidence, and no Claude-only FSM edges.

## Blockers

- **No per-call usage hook.** Tokens must come from transcript
  JSONL via a scraper, which ties to
  [2026-11-18-metric-collectors.md](2026-11-18-metric-collectors.md).
- **Run binding for subagents** is unproven: the Agent tool
  takes no env, so binding depends on the prompted command
  carrying `BP3_RUN_ID`.
- **Workflow opt-in.** Claude Code runs the Workflow tool only
  on explicit user request and keeps it under ~10 agents by
  default. Fine for trials, but it limits yolo fan-out
  ([2026-11-18-yolo-mode.md](2026-11-18-yolo-mode.md)).
- **Hooks must fail open.** On 2026-11-18 a missing `g` binary
  made `bin/bp3` exit 2 and blocked every tool in a Claude Code
  session (fixed the same day). Trials depend on that fix.
- **Which plan pays.** Muse allowance pressure is separate from
  Claude usage. Name the budget before trial 2.

## Promotion trigger

Thaw when a graph is first conducted from a Claude Code session
and needs a child Run, or when yolo thaws and wants a third
engine.
