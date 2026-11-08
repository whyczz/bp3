# Muse workflows, engine hooks, and wardens

Question this serves: can bp3 build an execution engine on Muse
workflows and Pi hooks without rebuilding its Board inside a harness
feature? Reader: the human deciding the engine Quest split, and the
implementer of the engine seam and the Muse workflow test. Evidence date:
2026-11-07/08. Local environment: Muse Code 1.4.14-R7309.1,
`muse workflows list` returns no saved workflows.

## Map

### The Muse workflow API (v1, as installed)

- Invocation is the model tool `muse.workflow` with `{name, script,
  scriptPath, resumeFromRunId, expectedScriptHash, args}`. A `name`
  alone launches a saved workflow; inline `script` is persisted and
  returns a `scriptPath`; `scriptPath + resumeFromRunId` resumes.
  Source: [Run multi-agent workflows](https://dev.meta.ai/docs/muse-code/workflows);
  reverse-engineering detail in
  [workflows-tools.md](https://github.com/hypery11/oh-my-musecode/blob/HEAD/research/musecode/workflows-tools.md).
- Scripts are JavaScript on an embedded V8 host (API v1). Globals:
  `agent`, `pipeline`, `parallel`, `phase`, `log`, `args`, `budget`.
  No network, imports, timers, `Date.now`, or `Math.random` in the
  script; the engine replays it deterministically from the top.
- `agent({input, agentType, schema, isolation, label})` runs one
  child; `pipeline(items, ...stages)` and
  `parallel([requests])` fan out. Caps: 16 concurrent children, 1000
  total child calls per run, inline schemas limited to a closed
  JSON-Schema subset (4 KiB, depth 16).
- There is no per-call `model` or `effort` in v1. Model routing by
  role (cheap author, strong reviewer) happens through separate
  parent sessions, not inside one workflow script. There is no
  in-script human gate and no steering of a running child; the TUI
  offers pause/skip/restart/cancel out of band. A v2 steering API
  exists as binary literals for an older build and is not proven
  live in 1.4.14.
- A workflow returns one JSON value to its parent session. There is
  no SQLite or Board sink. Board writes happen through the parent
  Controller calling Board ops, or a child shelling to the bp3 CLI
  if its tool grant allows it (not probed live).
- Saved workflows are plain `.js` files under
  `.agents/workflows/` (project) or the user config workflows dir.
  Crash recovery needs a retained session directory; temporary runs
  cannot recover after exit. Whether the V8 engine executes on this
  aarch64 build is unproven — the CLI responds, no live run was made.

### bp3's current hook surface

- The only live hook is the Pi bridge: lifecycle signals (`ready`,
  `heartbeat`, `busy`, `settled`, `took_over`, `release`,
  `permission-start/end`, `observed`, `exited`) over a Unix socket
  into Board transactions. See
  [bridge.ts](../../plugins/harness-pi/bridge.ts) and the signal
  handler in [run_ops.ml](../../core/board/run_ops.ml).
- Every Board op writes a receipt and an event row in one
  transaction; events carry a global sequence cursor. See
  [board.ml](../../core/board/board.ml) and the schema in
  [store.ml](../../core/board/store.ml).
- Missing today: transcript access (the ready signal's session file
  is stored, never read), token/cost usage (snapshot hardcodes cost
  to null), tool-call events, and per-plugin event cursors. Callers
  are Controller, Worker, Bridge, Runtime — no Observer role exists
  in [authority.ml](../../core/board/authority.ml).
- The MVP design already promises the missing piece: per-plugin
  event cursors, idempotent delivery, a disable switch, and the rule
  that plugins never write the Board or spawn work. See
  [bp3-control-mvp.md](../designs/bp3-control-mvp.md) plugin rules.

### Topology evidence (from the code, not preference)

- A concurrent author+reviewer loop is impossible on today's schema:
  a unique index allows one live Run Board-wide, `reserve` requires
  generation 0, and no reviewer role exists. Any loop work starts as
  an explicit schema and authority change.
- The fixed author/reviewer loop is a degenerate finite state
  machine: Authoring, Reported, Reviewing, then Land or a new
  generation of Authoring, guarded by ready/current-generation/
  deadline checks that already exist.
- A configurable DAG was explicitly rejected in the MVP design
  (no general graph vocabulary, no workflow DSL) and the engine
  Quest keeps workflow DSLs out of scope.

## Forces

- Context rent dominates observed pain: fresh children re-buy
  context. Workflow children cost roughly 30k–150k tokens each, so
  wide fan-out is a budget decision, not a free parallelism win.
- Ephemerality versus durability: workflow children cannot be
  steered, blocked-and-resumed, or recovered individually; the Board
  is what survives a killed Controller (the kill-Controller recovery
  test is an MVP acceptance check, not a nicety).
- Harness drift: the workflow API is versioned, partly
  reverse-engineered, and locally unexercised. Anything bp3 builds
  on it needs conformance spikes and contract tests, pinned per
  version.
- Trust is cooperative, not hostile: transcripts contain prompts,
  file contents, and possibly secrets. A scraping warden is itself
  an exfiltration target and must be bounded like one.
- Backpressure is real: a slow observer must never block Board
  writes. Observation has to be lossy for observers, never for the
  ledger.

## Options

- **Fixed loop as FSM (lean: build this first).** Formalize existing
  Run states; add a `role` column and per-role generations. What it
  takes: one additive migration plus invariant tests. What it
  breaks: the one-live-Run invariant, deliberately. Counter-case:
  if Exp 1 shows ceremony/provider waits dominate, even this is
  wasted work — the loop is not the bottleneck.
- **Configurable DAG.** What it takes: graph schema, validation,
  join semantics, budget/retry per node. What it breaks:
  understandability (the MVP's core data-model requirement) and
  reintroduces scheduling/backpressure bp3 deliberately avoided.
  Wins only if two or more distinct topologies are observed in the
  wild and the fixed loop measurably fails.
- **Hooks: pointers-only wardens (lean).** New event kinds carry
  token counts, tool names/durations, and transcript pointers
  (file + offset), never content. Wardens follow the events cursor,
  may lag with an explicit gap marker, and act only through existing
  authorized ops (cancel, steer, a fresh review Run). Transcript
  content fetch is a separate audited operation.
- **Hooks: full transcript scraping.** Buys deep review/drift
  analysis; pays with the largest privacy and retention surface.
  Only behind per-Quest scoping, redaction before insert, TTL, and
  an audit row for every fetch.
- **Doing nothing.** The bridge signal set covers the Pi crew today.
  Cost: no cost accounting (cost stays null), no cross-engine
  observability, and every new engine invents its own reporting.

## Open questions (ranked by what they change)

1. Block/resume versus block-then-respawn for ephemeral children.
   Changes the blocker contract everywhere. Recommended default:
   block-then-respawn with a new generation; revisit only if a spike
   proves resumable steering. Owner: human, with engine MVP Quest Exp 4 evidence.
2. Does the V8 workflow engine actually execute on this machine,
   and can a child reach the bp3 CLI through its tool grant? Gates
   the whole Muse spike. Default: assume CLI-only until a live
   child run proves otherwise. Owner: implementer, in engine MVP Quest Exp 4.
3. Warden scope: pointers-only versus audited content fetch.
   Changes the privacy surface permanently. Default: pointers only.
   Owner: human.
4. When does configurability earn its keep? Default trigger: two or
   more distinct topologies observed, plus Exp 1 evidence that
   scheduling (not context, ceremony, or provider) is the
   bottleneck. Owner: human, at the Quest split gate.
5. Reviewer independence: same model fresh context, or different
   model? Default: same model, fresh context, verdict bound to the
   exact commit; measure disagreement before routing models.
   Owner: implementer, in the loop exp.

## What I did not verify

- No live workflow run: V8 execution on aarch64, child tool grants,
  per-child routing precedence, and v2 steering are all unproven in
  1.4.14. Fine-grained API literals come from a 1.0.1
  reverse-engineering doc and may have drifted.
- Muse observability claims (hook names, JSONL shapes) are general
  knowledge used as design reference, not verified against Muse
  source in this repo.
- All speed and context-rent comparisons are goals until Exp 1
  measures the baseline; Board cost is currently hardcoded null.
