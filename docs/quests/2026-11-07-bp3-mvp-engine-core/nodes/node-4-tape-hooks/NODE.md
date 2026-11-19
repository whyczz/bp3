---
date: 2026-11-07
goal: ../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — Tape and hooks

## TL;DR

Every Run leaves a complete tape and a factual ledger with no
screen-scraping: the launcher captures verbatim output with
`tee`; hooks emit deliberate facts as event lines through
`bp3 q hooks`. Tape is evidence; the ledger is truth;
neither is built from the other.

Status: **proposed, not implemented or verified.** The earlier
record for this exp lives at
[../2026-11-07-tape-hooks.md](../2026-11-07-tape-hooks.md) and
predates the settled design; this record supersedes it where
they differ.

## Demos

### Observed — hook probe on this build (2026-11-13)

A probe `.muse/hooks.json` logging all 17 events, one
headless run of a two-child workflow:

```text
17:51:29 SubagentStart  child session 73937dbf... (probe child one)
17:51:33 SubagentStop   child one done
           <- zero hook events: the workflow JS ran here
17:51:34 SubagentStart  child session 73937ebf... (probe child two)
17:51:38 SubagentStop   child two done
PreToolUse payload:  "tool_input":{"command":"echo probe-child-one",...}
PostLLMCall payload: "usage":{"input_tokens":33250,"output_tokens":209,
                      "cached_tokens":0,"reasoning_tokens":119}
```

Observed, verbatim from the probe log: project-tier hooks
fire; workflow children are real sessions; the JS layer is
hook-invisible; the full command text (and therefore the
env preset) is witnessable; token usage is real.

### Observed — env preset in child commands

`envPreset(edge, cycle)` in `induct-exp.js` puts
`BP3_RUN_ID=<ts>-<edge>-<harness>-<model>-c<cycle>
BP3_QUEST=<q> BP3_EXP=<e>` on every stage edge command and
on the first command via the tape preamble.
`test/induct-exp.test.mjs` (mock host, in `make check`)
asserts all four stages carry it and that the run folder
matches `BP3_RUN_ID`.

### Design trace — one Run, hooks live (not built yet)

```text
child's first command (env preset on it)
  -> PreToolUse: bp3 q hooks witnesses BP3_RUN_ID, binds
     session_id -> run_id, writes run_started {edge, cycle, session_id}
  -> child calls bp3 q u submit ... (refused: E_DIRTY_TREE)
  -> PostToolUse: refused {code: E_DIRTY_TREE, attempted: submit}
  -> PostLLMCall xN: tallied in memory by the emitter
  -> Stop: usage_recorded {input_tokens, output_tokens, cached_tokens,
     reasoning_tokens, wall_ms, started_ts, settled_ts}
  -> edge verdict lands: run_settled {outcome}
killed instead of settled -> next SessionStart sweeps:
  run_unsettled {last_seen_ts}
```

```python
def run(edge, exp):
    run_id = f"{utc_ts()}-{edge}-{harness}-{model}-c{exp.cycle}"
    with tee(f"experiments/{exp}/runs/{run_id}/tape.log"):
        outcome = execute(edge)              # hooks mark tool/turn boundaries
    bp3_q_u(exp, edge, verdict=outcome)      # facts enter the ledger here
    commit(exp.branch, [tape, notes])        # one commit, at settle
```

| Part | Carries |
|---|---|
| Run id | `<ts>-<edge>-<harness>-<model>-c<cycle>`, UTC compact (`20261107T143022Z-review-muse-code-muse-wonder-1.0-c1`); timestamp gives uniqueness, an existing folder fails fast |
| Tape | verbatim executor output including crashes; zero agent cooperation |
| Hooks verb | `bp3 q hooks`: the emitter's only entry. Registered as the hook command; reads one hook event JSON from stdin, self-gates (bp3 repo, bound Run, fail-open), resolves the Run binding, and writes event lines through the binary's internal fact writer. There is no hand-invoked fact door: facts are machine-emitted, and nobody — model or human — mints a `usage_recorded` line by typing. Fixtures test it by piping payload JSON on stdin. Event lines carry `event`, `ts`, `run_id` and kind fields — never `edge`/`from`/`to`, so the state fold skips them by construction; dedupe by `run_id + kind` inside the writer |
| Names (Round 6, settled) | Event kinds are past tense, one per after-completion hook: `SubagentStart`/`SessionStart` -> `run_started`; `Stop`/`SessionEnd` -> `run_settled`; stale sweep at `SessionStart` -> `run_unsettled`; `PostLLMCall` -> `usage_recorded`; `PostToolUse` (refusal seen) -> `refused`; `PostToolUse` (lint exit seen) -> `lint_checked`. Edges stay present/imperative; facts and states stay past |
| Event kinds | `run_started` {edge, cycle, session_id} · `run_settled` {outcome} · `run_unsettled` {last_seen_ts} · `usage_recorded` {input/output/cached/reasoning tokens, wall_ms, started_ts, settled_ts} · `refused` {code, attempted edge — captured by the hook watching the refused `bp3 q u` response} · `lint_checked` {check, pass, or fail + first failing check} |
| Hook markers | tool/turn structure inside the tape |
| Hook facts | lifecycle and usage only — `run_started`, `run_settled`, `run_unsettled`, `usage_recorded`, `refused`, `lint_checked` — as **event lines** in the exp ledger through a bp3 q fact verb (Round 3 names it). Event lines carry no state change: the fold skips them for state and reads them for the scorecard. Hooks never emit verdicts or edges; they cannot judge |
| Hook inputs | Eight events only: `SessionStart`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostLLMCall`, `SubagentStart`, `SubagentStop`, `Stop`/`SessionEnd`. Every payload carries `session_id`, `cwd`, `model`; tool events add the tool and its response; `PostLLMCall` adds real `usage` (the payload's own field: input/output/cached/reasoning tokens) |
| Timestamps | Every event line carries `ts` (RFC3339 UTC, host clock). `usage_recorded` is one line per Run at settle: `{input_tokens, output_tokens, cached_tokens, reasoning_tokens, wall_ms, started_ts, settled_ts}` — aggregates of actual `PostLLMCall` payloads, never estimates |
| Registration | Project tier only: `bp3 skills install` drops `.muse/hooks.json` into bp3-enabled repos (same delivery as `induct-exp.js`), one command for all eight events: `bp3 q hooks`. Repos without the file never fire. Hooks fire in the main session and in workflow children alike (both are real sessions) |
| Guards | Emitter self-gates on every event: bp3-enabled repo (`bin/bp3` + `docs/quests/` at the repo root), an active bound Run (the run registry), fail-open on any error (exit 0, write nothing, never block a tool), reentrancy flag so the emitter never observes its own `bp3 q` calls, and dedupe by `run_id + kind` at the fact verb (parent and child can witness the same fact) |
| Binding | The workflow API exposes no per-child env, so children inherit the parent process env and binding cannot be inherited. It is **witnessed** instead — nobody hands the hook anything; it observes the binding in a command it was already watching. Explicitly: (1) `induct-exp.js` prefixes the child's first shell command for the stage: `BP3_RUN_ID=<ts>-<edge>-<harness>-<model>-c<cycle> BP3_QUEST=<quest> BP3_EXP=<exp>` plus the `BP3_HARNESS`/`BP3_MODEL` identity prefix (the stage's edge command repeats the same prefix). (2) `PreToolUse` fires before the command runs; its payload carries `session_id`, `cwd`, and the full `tool_input.command` text. (3) `bp3 q hooks` regex-extracts `BP3_RUN_ID`, `BP3_QUEST`, `BP3_EXP` from that text (first match per session wins; a later conflicting prefix in the same session is ignored and noted) and records `session_id -> run_id` in the run registry. (4) Every later event for that `session_id` resolves through the registry: `usage_recorded`, `refused`, `run_settled` all attach to that Run. Failure modes are explicit: no prefix witnessed -> the session is unbound, the hook writes nothing and exits 0 (fail-open); prefix witnessed but no matching run folder -> unbound, same handling. No bind verb or bind edge exists; the tape preamble already guarantees a first command per stage, so there is always a command to witness |
| Hook coverage (observed) | Live probe on this build (2026-11-13): project-tier `.muse/hooks.json` fires; workflow children are real sessions with their own session ids firing `SubagentStart/Stop`, `Pre/PostToolUse`, `Pre/PostLLMCall`; the workflow JS between children emits zero hook events; `PreToolUse` payloads carry the full `tool_input.command` (witnessed prefix is parseable); `PostLLMCall` payloads carry real `usage` {input_tokens, output_tokens, cached_tokens, cache_read_tokens, reasoning_tokens}. Reminder subagents also fire hooks — guards must filter, as designed |
| Binding impl | `induct-exp.js` `envPreset(edge, cycle)` applied to all four stage edge commands; `tapePreamble` instructs the prefix on the FIRST command. Durable test `test/induct-exp.test.mjs` (mock host, wired into `make check` via `test/induct.sh`) asserts every stage's commands carry `BP3_RUN_ID` matching its run folder |
| Env preset | Concept name for what `envPreset(edge, cycle)` produces: the env vars set before the child workflow agent runs — `BP3_RUN_ID`, `BP3_QUEST`, `BP3_EXP`, plus the `BP3_HARNESS`/`BP3_MODEL` identity. The child never chooses or computes them; the hook witnesses the preset in the first command. Renamed from "stage prefix" in Round 7: preset names the act (set in advance), not the string |
| Death | A killed session may never fire `SessionEnd`: on any `SessionStart`, the emitter sweeps stale unsettled run records and emits their `run_unsettled`. `Stop` is a checkpoint marker only, never a settle |

| Field | Value |
|---|---|
| Intent | Every run leaves a complete tape and a factual ledger without screen-scraping |
| Lane | standard |
| Output | Tape capture by the launcher script (never a model instruction); hook annotation + event-line emission through bp3 q; mechanical lints as scripts under `make check` |
| Ownership (Round 5, settled A) | Split by trust: tape by the launcher (`tee`, crash-proof, zero agent cooperation); lifecycle/usage facts only via `bp3 q hooks` (machine-emitted, never typed, never judged); mechanical checks as plain scripts, hook witnesses exit codes for `lint_checked`, no LLM in the loop. Rejected: B (hooks do everything — a hook dies with its session, tape loses crash survival), C (scripts scrape CLI output into facts — the tape rule forbids that channel) |
| Deliberately open | Tape-by-harvest (option D): skip `tee`, harvest the child's harness session log at settle by session id. Parked by the owner: mining does not exist yet, and gathering by run id from session logs is unproven. The icebox session-log-mining quest owns that question |
| Depends on | Exp 2 (the seam owns launching) + Exp 3 (facts land in the FSM ledger) |

## Acceptance

Tape cases already pass (`test/tape.sh`); the hook half
fails today: no `bp3 q hooks` verb, no installed
`.muse/hooks.json`, no event lines in any ledger.

| Case | Expected | Today |
|---|---|---|
| executor killed mid-tool-call | complete tape up to the kill | passes (tape) |
| settled Run | tape + `notes.md` on the exp branch as one commit | passes (tape) |
| hooks disabled (no `.muse/hooks.json`) | tape-only capture, no Run lost, no event lines | passes by absence |
| `bp3 q hooks` fed garbage on stdin | exit 0, writes nothing (fail-open) | fails: verb missing |
| hook fires outside a bp3 repo | exit 0, writes nothing | fails: verb missing |
| bound Run (env preset witnessed) | `run_started` then `run_settled` in the exp ledger, `session_id` on the first | fails: no emitter |
| Run ends | exactly one `usage_recorded` with real token fields from `PostLLMCall` | fails |
| session killed mid-Run | `run_unsettled` written by the next `SessionStart` sweep | fails |
| refused `bp3 q u` call | `refused` {code, attempted edge} line; state unchanged | fails |
| lint script exit witnessed | `lint_checked` {check, pass\|fail} | fails |
| two Runs in parallel (`submitted`) | distinct run folders and bindings, no cross-talk | fails: no bindings |
| any event line | carries `ts`, `run_id`, no `edge`/`from`/`to`; fold skips it | fails |

## Acceptance test (goal block)

- **Objective:** wire launcher `tee` capture (done) and
  `bp3 q hooks` event emission so every Run leaves a
  complete tape and the ledger gains facts only through
  the fact writer.
- **Prove by:** pipe fixture payloads into `bp3 q hooks`
  (garbage, foreign-repo, bound/unbound sessions) and
  assert exit codes and ledger contents; run one live
  `induct-exp` with hooks installed and read the exp
  ledger; kill a child mid-Run and sweep.
- **Done when:** every Acceptance case passes and a text
  search proves no ledger line's contents derive from
  tape text.

## Context

A run's output used to live in a watched pane and die with
it, so the only record of a four-hour bounce was folklore.
The tape ends that: capture is a launcher property, not a
favor the agent does, and it survives crashes and hook
failures alike. Hooks sit on the other trust level — they
emit facts deliberately, at the moment a fact happens, and
those facts become ledger lines through the same `u` door as
everything else. Keeping the layers apart is the whole
design: the day someone parses tape text into facts, screen
output becomes a state channel, and every formatting change
is a silent state change.

Costs ride this exp too: token/usage markers are what let the
scorecard price a Run instead of hardcoding null.

Edge cases: a Run that never settles leaves its tape
uncommitted — recovery reads the branch, not the worktree, so
an unsettled tape is a local artifact until a later pass
commits it. Run-id collision means two Runs claimed the same
second, edge, harness, model, and cycle: that is a duplicate
dispatch, and failing fast names it instead of merging two
tapes into one folder. Warden consumption of the ledger is
out of scope here (decided: not yet); this exp only produces
the record a warden would later eat.
