---
date: 2026-11-07
quest: ../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Tape and hooks: capture everything, emit only facts

## TL;DR

Every executor run leaves two artifacts: a `tape.log` (verbatim
output, captured by `tee` at launch, no agent cooperation needed)
and ledger lines (deliberate facts emitted by hooks through
`bp3 invoke`). The tape is for autopsies; the ledger is for
decisions; the ledger is never built by parsing the tape.

Status: **proposed, not implemented or verified.** All acceptance
checks below are unrun.

## Context and scope

Today a run's output lives in a Zellij pane and dies with it. The
Pi bridge (`plugins/harness-pi/bridge.ts` on the quest branch)
emits lifecycle signals to the Board, but there is no durable
per-run output artifact, no tool/turn structure, and cost is
hardcoded null in the Board snapshot
(`core/board/store.ml` on the quest branch). The hooks dossier
([Muse workflows and hooks](../../../dossiers/muse-workflows-hooks.md))
sketches event kinds and cursor-based consumption; this exp covers
only production of the tape and facts. Warden consumption is out
of scope (decided: not yet).

In: launcher-level `tee` capture; Pi bridge markers and ledger
emission; Muse settings hooks doing the same; per-run folder
layout (`runs/<id>/tape.log`, `runs/<id>/notes.md` for authored
lessons). Out: parsing tape text into events, warden subscribers,
transcript content retention beyond the tape itself.

## Mini-design

Two layers with different trust properties:

```text
launcher:  exec > >(tee runs/<id>/tape.log) 2>&1
           └─ verbatim capture, survives agent crashes and
              hook failure; gitignored by default, promoted
              into git only when it becomes evidence

hooks:     Pi extension events (agent_start, agent_settled,
           input, tool boundaries) and Muse settings hooks
           (PreToolUse/PostToolUse/Stop equivalents)
           ├─ append markers into tape.log (tool/turn structure)
           └─ emit ledger events via bp3 invoke:
              edge_taken, verdict, usage, settled, exited
```

Invariants:

- Ledger lines are emitted at the moment the fact happens, by the
  hook or the invoking Controller — never inferred from tape text.
  This is the runtime's existing no-screen-scraping rule applied
  to files.
- Tape capture must not depend on the agent: process-level `tee`
  at spawn (the launcher in `core/runtime/launcher.ml` on the
  quest branch owns the wrap),
  so a hung or killed executor still leaves a complete tape up to
  the kill.
- Hook failure degrades to tape-only. A dead hook loses facts, not
  the run; the gap is itself recorded when the next hook fires.
- Ledger lines carry `seq`, timestamp, run id, edge, actor,
  commit(s), and a `--reason` on judgment edges, per the Quest's
  invoke design. Raw logs may contain secrets: tapes stay out of
  git unless deliberately promoted, and promotion is a human or
  Controller act, never automatic.

Muse hook names above are from general Muse knowledge, not
verified against the local Muse install; the first
implementation step confirms them live before relying on them.

## Acceptance and evidence

Proposed checks, all unrun:

1. Kill an executor mid-tool-call: `tape.log` contains output up
   to the kill; the run is reconcilable as stale with no
   fabricated completion.
2. One toy exp end to end: ledger lines exist for every edge
   taken, each traceable to a hook emission or an invoke, none
   derived from tape text (checked by corrupting tape text and
   confirming the ledger is unchanged).
3. Hooks disabled: run completes tape-only; the ledger gap is
   explicit, not silent.
4. Usage lines land per run end, replacing the hardcoded null
   cost with observed tokens where the harness reports them.

## Runbook / recovery

Nothing to run yet. When implemented: tapes live under the quest's
`runs/` folders on the executor's host; a missing tape means the
launcher wrap failed before spawn (check launch staging), a
missing ledger with a present tape means hooks failed (check the
extension/hook load). Rollback is removing the wrap: executors run
exactly as today.

## Risks and next steps

- Risk: tape volume and secret leakage. Mitigation: gitignored by
  default; promotion is deliberate; retention is a follow-up
  decision, not this exp's.
- Risk: hook surfaces differ per harness and drift per version.
  Mitigation: the tape layer carries the guarantee; hooks are
  best-effort structure on top.
- Next step: confirm Muse hook names and Pi tool-event coverage
  live, then implement the launcher wrap first (smallest slice
  with standalone value).
