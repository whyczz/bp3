---
status: proposed
home_repo: bp3
date: 2026-11-15
---

# bp3-supervisor-mvp-and-pi-muse-enablement

## TL;DR

Children are nondeterministic; their logs are not.
Every harness writes a session log (its write-ahead
log). This Quest builds `bp3 harness`: a supervisor
that finds a Run's session log, watches it, folds it
(with pid liveness) into derived lifecycle, and
loops like a game engine — tick, derive, act — until
done or timeout. Built MVP-first on the CLI path,
backtested against the session-log corpus we
already own, proven live on a muse toy quest, then
carried to pi.

## ELI5

A child agent says "I'm done" and sometimes lies,
hangs, or dies quietly. Instead of trusting the
child, we read the diary its harness kept anyway —
every command, commit, refusal, and exit — and a
deterministic supervisor works out what actually
happened. Like database recovery replaying a
write-ahead log: state is folded from the trace,
never narrated by the worker.

## Terms

| Term | Meaning |
|---|---|
| `bp3 harness` | the CLI door for harness-facing machinery: `supervisor`, `find-session-log`, `watch`, `desk` |
| supervisor | the loop: spawn/monitor children, tick-fold-derive-act, until done/timeout/human gate; never does child work |
| WAL | a harness's own session log (write-ahead log): commands, tool results, usage, exits, written by the harness runtime |
| find-session-log | lookup verb: run-id <-> session-id <-> WAL file, per harness (`muse`, `pi`) |
| watch | blocking verb on one Run: exit / WAL growth / settle row, with timeout |
| monitor | liveness senses: pid alive, exit code/signal, WAL growth/close |
| watchdog | the monitor's reflex inside watch: silence budget, then SIGTERM -> SIGKILL |
| mailbox | per-Run `.jsonl` event file under `.git/bp3-run-events/`; one writer, append-only |
| lifecycle | derived, never stored: `spawned / running / settled / orphaned` |
| trace | one Run's folded event sequence (bp3 calls, commits, refusals, exits) |
| backtest | replaying the fold over stored WALs; a findings machine, not a gate |
| `W_SENTINEL_BLIND` | warning: WAL source missing or reshaped at probe time; work proceeds, observability degraded |

Spellings sync with the canceled pi quest's contract
artifact (`docs/engine-contract/`) and FSM: edge
names, `E_*` codes, and run-id shape are adopted.

## Demos

**Demo 1 — the loop (design trace).**

```text
bp3 harness supervisor --quest <toy>
  tick 041: run A running (WAL grew 2s ago)
  tick 118: run A settled; run B silent 601s -> TERM/KILL
  tick 119: B orphaned; railway advances; exit 0
```

**Demo 2 — backtest (design trace).** Replaying the
2026-11-15 pi-quest corpus, the fold surfaces:
exp-2 c2's author submitted then fossilized; two
2b authors refused with `E_BINDING_REFUSED` and
stopped honestly. Findings list -> fix proposals
for `bp3 q u`, bindings, adapters. Nothing must
pass; everything must be legible.

## Goal and why

Four blocked grades in one day, one seam: Runs
unwitnessed or unsettleable though the work was
fine. Witness machinery grew per-engine tricks
because each harness was asked to *emit* facts at
event time. The inversion: harnesses already
*record* everything in their WALs; bp3 should find,
watch, and fold recordings — not solicit testimony.

## Success picture

`bp3 harness supervisor` drives a muse toy quest
(flappy bird, three.js, subagents) end to end with
derived lifecycle and no LLM polling; backtests
over muse and pi corpora produce a concrete fix
list for `bp3 q u` and the adapters; the same
supervisor then drives the pi toy quest after a
design rethink under the sentinel pattern.

## Scope

| In | Out |
|---|---|
| `bp3 harness` door: supervisor loop, find-session-log, watch, desk | parsing WAL *content* for meaning (mechanical facts only; tape never parsed into state) |
| WAL lookup/fold for muse + pi | permanent daemon (the loop is one invocation; rerun freely) |
| backtests as findings (fixes to `bp3 q u`, adapters) | SQLite/Redis as truth (rebuildable index later, out of scope) |
| supervisor as bp3's mechanism for muse induct | pi conductor revival before Exp 9's rethink |
| `bp3 worktree` -> `bp3 harness desk` API migration | new FSM states (lifecycle stays derived) |

## Human touchpoints

- Framing approval (this file) — owner.
- Backtest findings review (Exps 6-7): owner picks
  which findings become `bp3 q u` fixes.
- Exp 9 pi rethink: owner gate before pi work.
- `quest_fin` promotion — owner, after demo.

## Exps

### Phase A — initial setup (MVP mechanism)

### Exp 1 — supervisor-cli — [record](experiments/exp-1-supervisor-cli/EXPERIMENT.md)
`bp3 harness supervisor`: the game loop. Tick =
fold, derive, act; exits on done/timeout/human
gate. OCaml in the binary, not a shell script.

### Exp 2 — find-session-log — [record](experiments/exp-2-find-session-log/EXPERIMENT.md)
`bp3 harness muse|pi find-session-log`: run-id
<-> session-id <-> WAL file lookup, both harnesses.

### Exp 3 — watch-run — [record](experiments/exp-3-watch-run/EXPERIMENT.md)
`bp3 harness muse|pi watch --run-id | --session-id`:
blocking done-signal over the found WAL + pid,
with silence watchdog and timeout.

### Exp 4 — supervisor-mechanism — [record](experiments/exp-4-supervisor-mechanism/EXPERIMENT.md)
bp3 uses the supervisor as its mechanism for muse:
induct steps spawn/watch through it; per-Run
mailboxes replace the shared dict.

### Exp 5 — harness-desk-api — [record](experiments/exp-5-harness-desk-api/EXPERIMENT.md)
API alignment: `bp3 worktree` folds into
`bp3 harness desk`; callers and skills updated.

### Phase B — backtest (findings, not gates)

### Exp 6 — backtest-muse — [record](experiments/exp-6-backtest-muse/EXPERIMENT.md)
Replay the fold over the muse session corpus:
find bp3 invocations, commits, refusals; produce
the fix list. Need not pass; must be legible.

### Exp 7 — backtest-pi — [record](experiments/exp-7-backtest-pi/EXPERIMENT.md)
Same replay over pi session files from the
canceled pi quest, incl. its five known incidents.

### Phase C — live demo (muse)

### Exp 8 — muse-toy-quest — [record](experiments/exp-8-muse-toy-quest/EXPERIMENT.md)
A toy quest (flappy bird in three.js) driven by
subagents under the supervisor, end to end.

### Phase D — pi engine MVP

### Exp 9 — pi-sentinel-rethink — [record](experiments/exp-9-pi-sentinel-rethink/EXPERIMENT.md)
Rethink the pi engine design under the sentinel
pattern: what the canceled quest got wrong, what
the supervisor replaces. Owner-gated design exp.

### Exp 10 — pi-toy-quest — [record](experiments/exp-10-pi-toy-quest/EXPERIMENT.md)
The same flappy toy quest driven on pi under the
supervisor.

### Exp 11 — landing-wrapup — [record](experiments/exp-11-landing-wrapup/EXPERIMENT.md)
Quest-level wrap: scorecard, findings disposition,
landing demo input.

## Scorecard

Fields: supervisor drives observed, backtest
findings count + disposition, `W_SENTINEL_BLIND`
firings, wall time, context tokens, human-active
minutes — or "unmeasured", never zero.

## Risks and red chair

Strongest attack, recorded at framing: *"This is
the plugin layer wearing a quest's clothes — exps
land fine unwitnessed."* Answer: the gate question
is deferred, not dodged — the supervisor here is
bp3's *mechanism* (Exp 4), and whether its warnings
veto anything is decided at Exp 8's live evidence,
not pre-paid in framing prose.

Second attack: *"WAL formats drift; you'll fold
lies."* Probe checks the exact fields consumed;
drift fires `W_SENTINEL_BLIND` instead of silence.
Backtests (Exps 6-7) measure real drift on real
corpora before the live demo depends on it.

## Open questions

1. `bp3 harness` verb spellings vs existing doors —
   Exp 5 settles migration (aliases? hard cut?).
2. How much of the fold lives in OCaml vs per-engine
   scripts — Exp 1 defaults OCaml, revisits at Exp 9.
