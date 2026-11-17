---
date: 2026-11-14
goal: ../GOAL.md
exp: 6
status: proposed
---

# Exp 6 — Hooks

## TL;DR

The hook half of Exp 4, split out so it can travel its own
cycle: `bp3 q hooks` reads one harness hook event JSON from
stdin, self-gates, witnesses the Run binding in the env preset
on the child's first command, and appends past-tense event
lines (`run_started`, `run_settled`, `run_unsettled`,
`usage_recorded`, `refused`, `lint_checked`) to the exp ledger
through the binary's internal fact writer. Event lines carry
`event`/`ts`/`run_id` and never `edge`/`from`/`to`, so the
state fold skips them by construction. Tape capture is Exp 4's
launcher half and already passes (`test/tape.sh`).

Status: **implemented; fixture-green; one live harness run
observed (see below).**

## Acceptance

All cases in `test/hooks.sh` unless noted:

| Case | Expected |
|---|---|
| garbage on stdin | exit 0, writes nothing |
| hook fires outside a bp3 repo | exit 0, writes nothing |
| unbound session event | exit 0, writes nothing |
| reentrant `bp3 q hooks` call | no binding, writes nothing |
| preset witnessed, no run folder | unbound, writes nothing |
| bound Run | `run_started` then `run_settled`, `session_id` on the first |
| Run ends | exactly one `usage_recorded`, real `PostLLMCall` fields summed |
| session killed, binding stale (>900s untouched) | next `SessionStart` sweeps `run_unsettled` |
| live parallel Runs (fresh bindings) | `SessionStart` sweeps nothing; only the stale binding is swept |
| refused `bp3 q u` call | `refused` {code, attempted}; state unchanged |
| lint script exit witnessed | `lint_checked` {check, pass\|fail} |
| two Runs in parallel | distinct bindings, no cross-talk |
| any event line | `ts` + `run_id`, no `edge`/`from`/`to`; fold skips it |
| hook registration delivered | `bp3 skills install` writes `.claude/hooks.json` and merges the same hooks into `.claude/settings.json` (`test/skills.sh`) |

## Evidence

- Cycle 1 (cc115c5): emitter + `hooks.json` delivery +
  fixtures; `make check` green. Review: needs_fix — the
  `SessionStart` sweep marked every other unsettled binding
  `run_unsettled` with no liveness check, so a second session
  starting beside a live parallel Run wrote a false past-tense
  fact into its ledger.
- Cycle 2 (this exp's fix): bindings now carry
  `last_seen_epoch`, touched on every witnessed event; the
  sweep only marks bindings untouched for `stale_after_s`
  (900s). Fixtures cover both directions: a backdated killed
  binding is swept, fresh parallel bindings are not, and
  ageing only one of two parallel bindings sweeps only it.
- Live, 2026-11-14: a headless `claude` session in a scratch
  bp3 repo ran one prefixed `bp3 q` command. With hooks only in
  `.claude/hooks.json`, no binding was witnessed (no registry,
  no event lines). With the same hooks merged into
  `.claude/settings.json`, the ledger gained `run_started`
  (real session id), `usage_recorded`, and `run_settled` for
  that Run. Delivery now writes both files. Observed limit:
  the live `usage_recorded` carried zero tokens — this host's
  `PostLLMCall` usage did not reach the tally in that run;
  fixture payloads with real usage fields sum correctly.

## Deliberately open

- Registry writes go through one shared `.tmp` path with no
  locking; concurrent hook processes could collide. Sequential
  hooks are unaffected; left as a noted minor from cycle-1
  review.
