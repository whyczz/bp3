---
status: proposed
home_repo: bp3
date: 2026-11-15
---

# bp3-supervisor-mvp-and-pi-muse-enablement

> AUTO-RED-INK DRAFT — shadow decisions only. The
> original quest is untouched until the owner adopts
> this copy in a later red-ink session.

## TL;DR

Children are nondeterministic; their logs are not.
Every harness writes a tape. This Quest
builds a common lifecycle-derivation layer that
finds a Run's tape, folds mechanical facts
from it (with pid liveness where available), and
produces proof without asking the child to witness
itself. Muse keeps its native runtime as the
completion owner and uses the layer passively.
Pi, whose children are raw processes, additionally
gets active supervision: spawn tracking, blocking
watch, and a watchdog. Children produce work;
supervision produces proof; the ledger produces
state; the grader produces the grade.

## ELI5

A child agent says "I'm done" and sometimes lies,
hangs, or dies quietly. Instead of trusting the
child, we read the diary its harness kept anyway —
every command, commit, refusal, and exit — and a
deterministic reader works out what happened. Like
database recovery replaying a write-ahead log:
lifecycle is folded from the trace, never narrated
by the worker.

## Terms

| Term | Meaning |
|---|---|
| `bp3 harness` | the CLI door (owner-settled, round 2): `init-check`, `supervisor`, `find-tape`, `watch`, `desk`. `BP3_HARNESS` stays env-only identity, never a verb |
| init-check | startup probe verb: per harness, verify the tape source exists, the consumed fields are present and shaped as the adapter expects, and the adapter parses a sample. Emits `W_SUPERVISOR_BLIND` in `warnings[]` per failing harness; never blocks work |
| engine selection | where a Run exists (`watch`, `find-tape`), the engine is derived from the run-id's InitRecord — never restated. Stated only where no Run exists yet (`supervisor`, `init-check`). Engine words: `muse-code`, `pi`. A stated engine contradicting the InitRecord is a usage error |
| argv shape | identity is positional, decision inputs are flagged: `bp3 harness supervisor <quest> --engine muse-code`; `watch`/`find-tape` take `--run-id`. Every harness verb has a single-letter alias, door-scoped and tested in both spellings: `i`=init-check, `s`=supervisor, `f`=find-tape, `w`=watch, `d`=desk |
| durations | the unit lives in the flag name, the value is a bare positive integer: `--silence-seconds`, `--timeout-seconds`, `--grace-seconds`. `0`, negatives, and suffixed values (`30m`) are usage errors |
| supervisor | the one actor, two modes. Passive (muse-code): probe inputs, find evidence, fold lifecycle — never spawns or kills. Active (pi/raw processes): the control loop that also spawns, watches, and kills. Never does child work. ("sentinel" is dead; do not use it) |
| monitor | not a component: the pid/process/tape senses the supervisor and watch poll |
| watchdog | watch's enforcement reflex: silence budget, then SIGTERM -> SIGKILL |
| tape | bp3's word for a harness's session log: the recorded stream of commands, tool results, usage, and exits the harness runtime writes anyway (write-ahead log is the metaphor; `tape` is the spelling in code, CLI, and docs) |
| find-tape | lookup verb: run-id -> init record / session-id / tape path; reverse lookup must resolve uniquely or refuse |
| watch | blocking verb on one Run: exit / tape growth / close, with timeout; sole TERM/KILL owner |
| run derivation log | the sole persisted supervisor output per Run: `.jsonl` under `<git-common-dir>/bp3/run-lifecycle-derivations/`; supervisor-owned observation and lifecycle rows with source evidence pointers |
| derived Run state | per-Run `.json` snapshot under `<git-common-dir>/bp3/run-lifecycle-derivations/`; an atomically replaced, deletable cache folded from the derivation log and current sources |
| InitRecord | first derivation row, written by the launcher/supervisor before the child starts: run-id, harness, session-id if known, pid if live, log path if known, desk, start time, effective model/thinking. Code spelling: OCaml `init_record`; `SpawnRecord` is retired everywhere |
| lifecycle | derived Run state (`init / active / finished / orphaned`), never a second truth; the `.json` file is only its materialized cache |
| trace | the fold's output view: ordered mechanical facts for one Run |
| outcome | why a watch/supervisor call stopped (`settled`, `watchdog_killed`, `timeout`, `human_gate`); distinct from lifecycle |
| backtest | replaying the fold over stored tapes; a findings machine, not a gate |
| grader | reviewer: judges artifacts first, parsed events second, raw tapes only when needed |
| `W_SUPERVISOR_BLIND` | warnings-array value only: tape source missing or reshaped; work proceeds, observability degraded |

Spellings sync with the canceled pi quest's
QUEST.md contract section and the FSM: edge names,
`E_*` codes, and run-id shape are adopted.
`docs/engine-contract/` remains a to-build artifact,
not an existing authority.

## Design contract added by auto-red-ink

### Owners

| Engine | Completion/control owner | Lifecycle/proof owner | Experiment-state owner |
|---|---|---|---|
| muse | workflow runtime's natural completion | supervisor fold over tapes + spawn/pid evidence where available | `bp3 q` ledger/FSM |
| pi/raw process | supervisor + watch | supervisor fold over tapes + spawn/pid evidence | `bp3 q` ledger/FSM |

Muse subagents therefore do not get a redundant
process babysitter. The supervisor derives events for
audit, recovery, and backtesting; it does not
compete with Muse's runtime. Pi has no such
runtime, so the supervisor owns spawn/watch/kill.

### Owners / responsibility

| Actor | Responsibility |
|---|---|
| experiment agent | work and artifacts |
| supervisor | proof of what mechanically happened |
| `bp3 q` ledger | legal experiment state |
| grader | grade |

### Grader evidence ladder

In order; each rung only when the ones above leave
the verdict undecided:

1. The quest and exp records (what was asked).
2. Committed code and git diff at the exact commit.
3. Demos and tests, run — not read about.
4. Style (code-writer/code-reviewer discipline).
5. Tape, via derivation pointers first
   (`find-tape --entry`); the whole tape only
   when blocked, confused, or the work looks like it
   is lying. Escalation is allowed; defaulting to
   rung 5 is not.

### Lifecycle derivation

`init` = InitRecord only. `active` =
InitRecord, no finish evidence, pid alive where a
pid exists, and freshness within the named budget,
where `freshness = max(tape mtime, latest
derivation-observation timestamp)`. `finished` requires exit
observed (or a settle row) plus the harness's finish
evidence, and no live pid: a live pid is never
`finished`, whatever the tape tail says, and a row
alone never finishes a live child. Finish evidence
is per harness, proved on the real corpora
(followup.2), and only the last whole tape entry can
carry it:

| Harness | Finish evidence (last whole entry) | Exit entry |
|---|---|---|
| `muse-code` | `session.end` entry (close marker) | runtime `terminal` entry — a child tape ends here, with no close marker |
| `pi` | `session_closed` entry, or a final assistant entry with stopReason `stop` | process exit (pid dead); pi tapes never close |

A torn final tape entry (unterminated or
unparseable) is evidence of nothing: it finishes no
Run and is reported as `W_TORN_TAIL`.
`orphaned` = stale and pid dead/absent.
Derivation uses files plus live pid probes, never
an in-memory live set, so a restarted reader does
not orphan every active child.

Blindness adds no fifth lifecycle word. A blind
probe appends an observation row carrying
`W_SUPERVISOR_BLIND` and empty evidence data (no
pointer, no content, nothing fabricated), so the
log shows the gap instead of hiding it; lifecycle
keeps deriving from pid + InitRecord meanwhile.

### Simplification rule

No component may introduce another persisted
per-Run store. Normalized run events are an internal
record type passed between adapters, fold, and
verdicts — not a file family. mvp.5 owns deleting
the stores and duplicate writers this replaces.

### Local derived-log layout

All paths resolve from `git rev-parse
--git-common-dir`, never from a worktree's `.git`
file. Linked desks therefore share the same local
store while the store stays outside every worktree
and out of git history:

```text
<git-common-dir>/bp3/
  run-lifecycle-derivations/<run-id>.jsonl  supervisor observations + lifecycle
  run-lifecycle-derivations/<run-id>.json   current derived state cache
```

There is no target `run-events` store. Existing
per-Run event logs from earlier work are read-only
migration inputs for the supervisor, never new write
targets.

The derivation row names its source evidence as a
pointer — tape path, the entry's own id
(muse `uuid`, pi `id`), byte range, size/mtime/digest,
pid probe — never raw session content. Consumers
(grader, conductor, debugging human) read the cited
entries only; nobody ingests a whole tape.
Pointers resolve mechanically, never by hand:
`bp3 harness find-tape --run-id <R> --entry
<entry-id>` verifies the digest, then returns that
one entry — widened by `--before-entries <n>` /
`--after-entries <n>` (non-negative integers,
default 0) when context is needed. Owned by mvp.2. The `.json`
snapshot records the same input fingerprints and is
written by temp-file + atomic rename. Readers use
it only when those fingerprints still match; graders
may force a refold. Deleting a `.json` snapshot must
change nothing except speed.

### CLI verdict contract

Long-running verbs stream NDJSON lifecycle-change
rows on stdout and end with exactly one normal JSON
verdict. Human tick prose goes to stderr or a
table rendering. Final verdicts split the fate of
the Run (`outcome`, `settled`, `lifecycle`) from
failure of the call itself (`{ok:false,error:{code,
facts,guidance}}`). `W_SUPERVISOR_BLIND` is only a
`warnings[]` value, never an outcome or error.

Exit classes carry the driver's next move: `settled`
exits 0 (natural finish); `watchdog_killed` exits
terminal; `timeout` exits retryable (call again, the
Run may still settle); `human_gate` exits
needs-human (page the owner, never auto-retry).
Exact integers adopt the binary's existing exit
classes; mvp.1 maps outcomes onto them.

## Demos

**Demo 1 — active supervision for a raw-process
engine (design trace).** Muse uses the same fold
passively; it does not need this loop to wake it.

```text
<harness-door> supervisor --quest <toy>
  tick 041: run A active (tape grew 2s ago)
  tick 118: run A finished; run B silent 601s -> TERM/KILL
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
*record* everything in their tapes; bp3 should find,
watch, and fold recordings — not solicit testimony.

## Success picture

Muse's runtime drives a toy quest (flappy bird,
three.js, subagents) while the supervisor derives
lifecycle and events from its tapes — no
redundant Muse supervisor loop and no LLM
polling. Backtests over muse and pi corpora
produce a concrete fix list for `bp3 q u` and the
adapters. After a design rethink, the active
supervisor drives the same toy quest on pi.

## Scope

| In | Out |
|---|---|
| `bp3 harness`: init-check, supervisor, find-tape, watch, desk | parsing tape content for meaning beyond enumerated mechanical facts |
| tape lookup/fold for muse + pi | permanent daemon (supervisor/supervisor invocations are rerunnable) |
| backtests as findings (fixes to `bp3 q u`, adapters) | SQLite/Redis as truth (rebuildable index later, out of scope) |
| supervisor as bp3's lifecycle/evidence mechanism for muse; active supervisor for pi | a second Muse process supervisor competing with Muse's workflow runtime |
| `bp3 worktree` -> harness-door `desk` API migration | new FSM states (lifecycle stays derived) |

## Human touchpoints

- Framing approval (this file) — owner.
- Backtest findings review (backtest.*): owner picks
  which findings become `bp3 q u` fixes.
- dogfood.2 pi rethink: owner gate before pi work.
- `quest_fin` promotion — owner, after demo.

## Exps

Exp display names are `<milestone>.<number> - <slug>`.
Folders and bp3 exp IDs use the dotless spelling
`exp-<milestone>-<number>-<slug>` because slugs
cannot contain dots.

### Milestone: mvp — initial setup

### mvp.1 - supervisor-cli — [record](experiments/exp-mvp-1-supervisor-cli/EXPERIMENT.md)
CLI door/verdict skeleton first, then the active
loop for raw-process engines. Tick phases are
`tell -> watch -> judge (fresh bp3 q r) -> finalize`;
watch is the sole killer. Live loop proof is
deferred until mvp.2-mvp.3 supply lookup/watch.

### mvp.2 - find-tape — [record](experiments/exp-mvp-2-find-tape/EXPERIMENT.md)
InitRecord-first lookup: run-id -> session-id /
tape path per engine. Session-id is a reverse
lookup input only, never the primary key.

### mvp.3 - watch-run — [record](experiments/exp-mvp-3-watch-run/EXPERIMENT.md)
Blocking done-signal over the found tape +
pid, with silence watchdog and timeout. Muse's
passive fold uses the same derivation without
taking control from its runtime.

### mvp.4 - supervisor-mechanism — [record](experiments/exp-mvp-4-supervisor-mechanism/EXPERIMENT.md)
bp3 adopts the supervisor as its lifecycle/evidence
mechanism for muse. Split out as substep mvp.4b:
run-lifecycle-derivations become the only persisted supervisor
output; shared dicts and per-Run event-log writes
are retired on both write and read paths.

### mvp.5 - delete-redundant — [record](experiments/exp-mvp-5-delete-redundant/EXPERIMENT.md)
Cleanup pass after the replacement works: inventory
the old witness machinery, prove shadow parity,
cut writers and readers over, then delete the shared
session map, child-prefix ritual, and other plumbing
the supervisor made redundant. Local shared maps are
converted to derivation logs before disposal.

### mvp.6 - harness-desk-api — [record](experiments/exp-mvp-6-harness-desk-api/EXPERIMENT.md)
API alignment: all nine existing worktree verbs are
mapped to the chosen desk door; golden verdict
fixtures are captured before migration.

### mvp.7 - grader-evidence-ladder — [record](experiments/exp-mvp-7-grader-evidence-ladder/EXPERIMENT.md)
The five-rung ladder becomes machinery: grader
instructions and `induct-grade` consume records,
diff, run demos/tests, style, then tape
pointers via `find-tape --entry`; whole-log
reads only on escalation.

### mvp.8 - muse-initrecord-writer — [record](experiments/exp-mvp-8-muse-initrecord-writer/EXPERIMENT.md)
RC1, promoted into MVP by owner: the induct
launcher workflows write InitRecord at the run-id
mint, before the child starts; passive supervisor
never does.

### Milestone: followup — red-chair concerns

### followup.1 - derivation-concurrency — [record](experiments/exp-followup-1-derivation-concurrency/EXPERIMENT.md)
RC2: append/rename discipline for
`run-lifecycle-derivations/` under concurrent
supervisors, proved with race fixtures.

### followup.2 - finish-evidence — [record](experiments/exp-followup-2-finish-evidence/EXPERIMENT.md)
RC3: per-adapter finish evidence (close marker,
exit entry, pid+grace) proved on real corpora;
feeds backtest.1/backtest.2.

### Milestone: backtest — findings, not gates

### backtest.1 - muse — [record](experiments/exp-backtest-1-muse/EXPERIMENT.md)
Replay the fold over the muse session corpus:
find bp3 invocations, commits, refusals; produce
the fix list. Findings do not gate, but corpus
denominator and incident match counts are reported;
parser crashes fail the exp.

### backtest.2 - pi — [record](experiments/exp-backtest-2-pi/EXPERIMENT.md)
Same replay over pi session files from the
canceled pi quest. Each finding must be consumed
by dogfood.2's keep/replace/drop table.

### Milestone: dogfood — use it ourselves

### dogfood.1 - muse-toy-quest — [record](experiments/exp-dogfood-1-muse-toy-quest/EXPERIMENT.md)
A toy quest (flappy bird in three.js) driven by
Muse subagents natively, with the supervisor deriving
lifecycle in parallel. Includes the owner gate
decision seeded by a blind-log Run.

### dogfood.2 - pi-supervisor-rethink — [record](experiments/exp-dogfood-2-pi-supervisor-rethink/EXPERIMENT.md)
Rethink the pi engine design under the supervisor
pattern: extension, dispatcher, and supervisor duties
are separated; the dispatcher keeps no second
watchdog. Owner-gated design exp.

### dogfood.3 - pi-toy-quest — [record](experiments/exp-dogfood-3-pi-toy-quest/EXPERIMENT.md)
First port/re-verify the pi binding from dogfood.2,
then drive the same flappy toy quest on pi under
active supervision.

### Milestone: landing

### landing.1 - landing-wrapup — [record](experiments/exp-landing-1-landing-wrapup/EXPERIMENT.md)
Quest-level wrap: scorecard, findings disposition,
and the landing walkthrough actually run.

## Scorecard

Fields: supervisor drives observed, backtest
findings count + disposition, `W_SUPERVISOR_BLIND`
firings, wall time, context tokens, human-active
minutes — or "unmeasured", never zero.

## Risks and red chair

Strongest attack, recorded at framing: *"This is
the plugin layer wearing a quest's clothes — exps
land fine unwitnessed."* Auto-red-ink answer: the
veto question is not silently pre-settled. dogfood.1
must seed a blind Run and record the owner's
`veto | warn-only` decision; until then the design
uses warn-only as the least-committal draft.

Second attack: *"Tape formats drift; you'll
fold lies."* Probe checks the exact fields consumed;
drift fires `W_SUPERVISOR_BLIND` instead of silence.
Backtests (backtest.1-2) measure real drift on real
corpora before the live demo depends on it.

## Open questions

The full owner list, options, and consequences are
in [DECISION-RECORD.md](DECISION-RECORD.md).
Headlines: final door name and engine grammar;
duration grammar; model/thinking inputs; env
precedence; aliases and reserved names; whether
supervisor warnings veto landing; tape and
desk survivor spellings; exit class for timeout and
human gate; desk alias versus hard cut; and the pi
face/pulse/adapter-placement choices.
