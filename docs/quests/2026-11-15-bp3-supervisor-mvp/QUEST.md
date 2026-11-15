---
status: proposed
home_repo: bp3
date: 2026-11-15
---

# bp3-supervisor-mvp

## TL;DR

Children are nondeterministic; their logs are not.
Every harness writes a session log (its write-ahead
log). This Quest builds the supervisor layer that
folds those logs — plus pid liveness — into derived
Run lifecycle state, replacing four hand-rolled
witness tricks that each blocked a grade. Proven
offline first: the fold must reproduce five known
incidents from the canceled pi quest's session corpus
before it supervises anything live.

## ELI5

A child agent says "I'm done" and sometimes lies,
hangs, or dies quietly. Instead of trusting the
child, we read the diary its harness kept anyway —
every command, commit, refusal, and exit — and a
small deterministic reader (the sentinel) works out
what actually happened. Like database recovery
replaying a write-ahead log: state is folded from
the trace, never narrated by the worker.

## Terms

| Term | Meaning |
|---|---|
| WAL | the harness's own session log (write-ahead log): commands, tool results, usage, exits, written by the harness runtime |
| adapter | one parser per harness WAL format (pi session JSONL, muse transcripts); emits the normalized event stream |
| sentinel | the deriving step: folds adapter stream + pid liveness into lifecycle; ephemeral, re-runnable, owns no memory |
| monitor | liveness senses: pid alive, exit code/signal, WAL growth/close |
| watchdog | the monitor's reflex: silence budget, then SIGTERM -> SIGKILL |
| mailbox | per-Run `.jsonl` event file under `.git/bp3-run-events/`; one writer, append-only |
| Run event | typed row: `run_started`, `heartbeat`, `usage_recorded`, `run_settled`, `sentinel_blind` |
| lifecycle | derived, never stored: `spawned / running / settled / orphaned` |
| trace | one Run's folded event sequence (bp3 calls, commits, refusals, exits) |
| ground truth | what actually happened, known only from `ledger.jsonl` + grade matrices (never from tapes or memory) |
| `W_SENTINEL_BLIND` | warning: WAL source missing or reshaped at probe time; work proceeds, observability degraded |

Spellings sync with the canceled pi quest's contract
artifact (`docs/engine-contract/`) and FSM: edge
names, `E_*` codes, and run-id shape are adopted,
not reinvented.

## Demos

**Demo 1 — backtest replay (design trace).** The
sentinel folds the 2026-11-15 pi-quest corpus. For
exp-2 c2's author session it emits: `submit` call
found, sha matches ledger, `run_started` present,
no settle marker, WAL silent after T → derived
`orphaned`. Ledger truth agrees. Incident reproduced
without reading a single ledger line first.

**Demo 2 — live drive (design trace).** A pi child
hangs on a dead provider. WAL stops growing; pid
alive. Sentinel crosses the silence budget, SIGTERM,
SIGKILL; fold derives `orphaned`, never `settled`.
Conductor's `bp3 q r` shows the warning and moves
the railway; nobody's context burned polling.

## Goal and why

Four blocked grades in one day, all one seam: Runs
unwitnessed or unsettleable, though the work was
fine. The witness machinery grew per-engine tricks
(typed prefixes, agent-link claims, synthetic
emitters) because each harness was asked to *emit*
facts at event time. The inversion this Quest
proves: harnesses already *record* everything in
their WALs; bp3 should fold recordings, not solicit
testimony.

## Success picture

A fold that reproduces the five known incidents
offline; a live sentinel deriving lifecycle for
muse and pi children from WAL + pid; per-Run
mailboxes; a grade gate that vetoes only "no real
run existed"; and a demo drive showing a hung child
killed, a blind-log run warned, and a clean run
settled — all observed, none narrated.

## Scope

| In | Out |
|---|---|
| WAL adapters (pi, then muse) + normalized stream | parsing log *content* for meaning (facts mechanical only; tape stays unparsed-into-state per standing rule) |
| sentinel fold + startup probe (`W_SENTINEL_BLIND`) | a permanent supervisor daemon (ephemeral first; daemon only on measured need) |
| per-Run mailbox writer migration (muse) | SQLite/Redis as truth (derived index allowed later, rebuildable, out of scope here) |
| bind-as-fold-key; hooks demoted to footprint-leavers | pi conductor/engine revival (canceled quest stays canceled; pi is a WAL tenant here only) |
| watchdog in pi dispatcher; gate-split in induct-grade | new FSM states (lifecycle stays derived) |

## Human touchpoints

- Framing approval (this file) — owner.
- Exp 6 (gate-split) changes grade policy — owner
  rules the matrix wording when the exp is framed
  for induct.
- `quest_fin` promotion — owner, after demo.

## Exps

### Exp 1 — wal-backtest — [record](experiments/exp-1-wal-backtest/EXPERIMENT.md)
Adapters for pi + muse WALs, a replay harness, and
the five-incident exam: the fold must reproduce
known history from raw logs before anything live.

### Exp 2 — sentinel-fold — [record](experiments/exp-2-sentinel-fold/EXPERIMENT.md)
The sentinel live: discover Runs, fold WAL + pid
into lifecycle, startup probe with `W_SENTINEL_BLIND`,
trace per Run on read.

### Exp 3 — mailbox-per-run — [record](experiments/exp-3-mailbox-per-run/EXPERIMENT.md)
Muse writer migrates to per-Run `.jsonl`; the
shared mutable dict becomes a folded view, then dies.

### Exp 4 — bind-at-startup — [record](experiments/exp-4-bind-at-startup/EXPERIMENT.md)
Binding becomes a fold key: session <-> Run derived
from WAL evidence; hooks stamp footprints only;
child-typed prefix retires to override.

### Exp 5 — await-watchdog — [record](experiments/exp-5-await-watchdog/EXPERIMENT.md)
Blocking await (exit/WAL-growth/fold race) plus
silence watchdog SIGTERM -> SIGKILL in the pi
dispatcher; muse conductor re-read pattern.

### Exp 6 — gate-split — [record](experiments/exp-6-gate-split/EXPERIMENT.md)
Skill exp: induct-grade matrix splits the witness
row — `run_started` gates, settled/usage warn.

### Exp 7 — supervisor-demo — [record](experiments/exp-7-supervisor-demo/EXPERIMENT.md)
End-to-end drive: hung child killed, blind-log run
warned, clean run settled; landing traces.

## Scorecard

Fields: backtest accuracy (5 incidents, pass/fail
each), live drives observed, `W_SENTINEL_BLIND`
firings, wall time, context tokens, human-active
minutes — or "unmeasured", never zero.

## Risks and red chair

Strongest attack, recorded at framing: *"This is
the plugin layer wearing a quest's clothes — by the
platform test, exps land fine unwitnessed."* True,
and the split is the answer: Exps 1-5 build
observability that is honest about being
observability; Exp 6 removes its veto. Settled
here, not parked: the railway orders proof (fold)
before policy (gate), so the demotion is earned.

Second attack: *"WAL formats drift; you'll fold
lies."* Mitigated by design, Exp 1/2: probe checks
the exact fields consumed, and drift fires
`W_SENTINEL_BLIND` instead of silent blindness.

## Open questions

1. Sentinel home: OCaml verb in `bp3 q`, or a
   script per engine? (Owner: engine team; Exp 2
   frames it, default OCaml for fold reuse.)
2. Muse WAL path/format stability across muse
   versions — Exp 1 measures on the stored corpus.
