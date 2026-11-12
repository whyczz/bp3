---
status: active
home_repo: bp3
date: 2026-11-07
---

# bp3-mvp-engine-core: the quest state machine

TL;DR
bp3 gains its core: a CLI and state engine where work moves as
clean commits through a small state machine, written only by
`bp3 q u`. When this Quest lands, a quest folder carries its own
state, any executor can take the next edge, and the Muse
executor test lives in its own Quest downstream of a stable core.

## Terms

- Quest: one unit of work with an authored railway of exps.
- Exp: one entry on a quest's railway, running the inner FSM.
- Run: one execution that takes an edge and leaves a tape.
- State: a condition of an exp (`todo`, `submitted`,
  `approved`, `blocked`, `landed`, `deleted`) — never a role,
  a command, or a “stage.”
- Edge: an attempted move named on the CLI under `u`
  (`submit`, `review`, `check`, `land`, `block`, `resume`).
- Transition: an accepted edge, recorded as one ledger line
  and one commit.
- Refusal: a judged “no” to an edge; JSON only, never a
  ledger line.
- Verdict: the binary's JSON answer to a call; review and
  check calls also carry a judgment value.
- Ledger: the append-only record of accepted transitions;
  at a branch tip, it is the truth.
- Tape: verbatim Run output; evidence, never parsed into
  facts.
- Cycle: the iteration count on an exp; data, never a state.
- Land: moving an approved exp into the quest branch —
  fast-forward, clean merge, or conflict back to `todo`.
- Tombstone: a `deleted` exp or quest whose record and
  branch ref are kept; nothing is removed for real.
- Railway: the quest's authored linear track of exps and
  fan-out groups; the engine navigates it up front, and a
  blocked entry blocks everything behind it.
- Fan-out group: sibling exploration exps run in parallel;
  members are not landable, exactly one follow-up lands.
- `quest_type`: the outer plan (knobs only, from `plans/`).
- `exp_type`: an exp's inner profile (FSM knobs, required
  checks, skill names).
- Engine: the bp3 FSM plus a harness — the whole
  execution system that takes edges and runs work.
- Harness: the third-party app host and its bundle —
  model, skills, hooks, and extensions (e.g. Muse
  Code, Pi, Codex). Harness and model are recorded per
  ledger line.

## Demos (design traces — no binary exists yet; nothing here has run)

```text
HAPPY PATH
  todo --submit c1--> submitted --review ship + check pass--> approved
       --engine autoland--> landed        (quest tip moves once)

BLOCKED RAILWAY
  submitted --needs_fix @ max_cycles--> blocked  [checkpoint committed]
  engine bubbles -> human: "resume, go simpler" (attested human)
  blocked --resume--> todo c2 -> fresh Run -> new commit -> submit

LLM MISFIRE
  todo + land -> E_ILLEGAL_EDGE {state: todo, legal_edges: [submit, block]}
  state unchanged, nothing ledgered, agent picks a legal edge

SESSION LOST
  machine dies at blocked -> clone anywhere -> bp3 q r
  inbox: [{quest, exp, reason, checkpoint, cycle, since}]  (folded live)
```

ELI5
Today every helper starts blank and pays full price to re-learn the
job; that rent, not typing speed, is the wait. So the coordinator
keeps the map in its own head, sends out helpers that inherit or
fork what it knows, and writes down what happened. You read the
summary, not the workshop floor.

## Goal and why

Replace the pane-crew execution model with an engine model whose
contract is context provisioning: `cold | warm | fork | subagent`.
The engine is a first-class bp3 component, not a caller detail:
this Quest specifies the bp3 CLI the engine calls and the contract
every engine must satisfy, while engine implementations are
harness-specific bundles (skills, hooks, extensions, and helper
code) built downstream. Every engine must: navigate the railway and
dispatch Runs; provision context; take transitions only through
`bp3 q`; autoland at `approved`; and resolve blocked exps by
bubbling them to the human-facing session, capturing the human's
decision, attesting it, and redispatching. Helper CLIs or scripts
are engine-side choreography only — state moves exclusively
through the bp3 binary. The contract grows by one test: if a
piece can die while an exp still travels `todo` -> `landed`
with the human gate intact, it is a plugin, not core. A plugin
is a contract plus implementations: one stable API (the
verdict/event JSON it receives, an idempotency key naming the
transition, an ack it returns) behind which implementations
fan out — the notification contract, for example, is one API
with Discord, Slack, iMessage, and desktop implementations.
Metrics, projects, warden, and notifications are plugins:
they consume verdicts and events, never write state, and
their failure never fails a transition. The predecessor Quest
[bp3 MVP: the loop on itself](../2026-11-05-bp3-mvp/QUEST.md) proved the
Board, brief/report ops, and gated landing, but its center bet —
fresh-context Workers in watched Zellij panes — makes every Run
re-buy its context. Four-hour coder/reviewer bounces were observed;
the human judges watchability and takeover to be comfort, speed the
requirement. This Quest keeps the proven record and landing layers
and rebuilds only how work executes.

## Success picture

The founding evidence is the owner's: the Pi loop was run by
hand and it sucks — no baseline exp is run. The engine contract
is specified (Pi extraction against it is frozen in the
[pi-engine icebox entry](../../icebox/2026-11-11-pi-engine.md));
the commit-state machine runs the toy exp end to end — submit,
review, check, CAS land — with guards intact. The Muse executor
test that proves interchangeability downstream lives in
[bp3-mvp-muse-workflows](../2026-11-07-bp3-mvp-muse-workflows/QUEST.md).
Landing is recorded here with the
measured context cost per edge, and limitations. Record layer as
decided after red chair: no SQLite Board — bookkeeping lives in
files in git: per-exp ledgers are the record, quest state is a
rollup, and `state.yaml` files are derived caches, written only
through `bp3 q <quest> u <exp>`. First slice landed as
`bp3 invoke` (rename owed in one change:
binary, tests, docs, skills) with the `default` quest_type
(one review round) and fixture tests in `test/invoke.sh`.

## Scope

In: the `bp3 q` CLI
scaffold; and the commit-state FSM (states, edges, guards,
YAML quest_type plans). Pi engine extraction is out — frozen
in the [pi-engine icebox entry](../../icebox/2026-11-11-pi-engine.md).
Inherited by reference: the canceled Quest's Exp 2
auto-land kernel candidate `9e1b1d0` and its gated-landing
contract. Downstream Quests:
[bp3-mvp-muse-workflows](../2026-11-07-bp3-mvp-muse-workflows/QUEST.md)
(Muse executor test), [bp3 engine, Pi executors](../2026-11-07-bp3-engine-pi.md)
(oh-my-pi, subagent extensions, or our own), and
[bp3 pi qol](../2026-11-07-bp3-pi-qol.md) (the Pi speed
meta), written alongside this one.
Out: warden/hook substrate (decided: not yet; the contract sketch
waits in the [hooks dossier](../../dossiers/muse-workflows-hooks.md)),
resurrecting pane takeover as a requirement (Zellij remains a
debug view only), foreign-TUI typing, multi-host or remote Workers,
arbitrary per-Quest graph editing (a DAG), and any change to the
frozen Exp 2 coordinator before its kernel is adopted or dropped
by explicit human decision.

## Human touchpoints

Quest framing (this file), escalations (success-picture change,
budget exhaustion, engine contract change), and Quest-to-master
promotion. Everything else is automated or it is listed here.

## Exps

Full Output, Acceptance, and Substeps for each exp live in its
own record under `experiments/`; this file keeps the railway.

| Exp | TL;DR | Acceptance, in one line | Depends on |
|---|---|---|---|
| 2 — CLI scaffold | The `bp3 q` CLI: verdicts, error codes, strict argv, identity env, blocked inbox | Fixture suite green: verdict shapes, error codes, both verb spellings, strict argv, identity, blocked inbox | none |
| 3 — Commit-state FSM | Six-state machine per exp, ledgers at branch tips, railway, autoland | Two executors alternate with identical guards; stale verdict refused; halt at the bound | Exp 2 |
| 4 — Tape and hooks | Tape per Run, hooks emit ledger facts, tape never parsed | Killed executor still leaves a complete tape; no ledger line derived from tape text | Exp 2 + Exp 3 |

Records:

- Exp 1 — Timed baseline: **killed by the owner** (ran the Pi
  loop by hand; it sucks — measurement unnecessary). Record kept
  as a fossil: [exp-1-baseline](experiments/exp-1-baseline/EXPERIMENT.md)
- Exp 2 — [CLI scaffold: u, discover, CRUD](experiments/exp-2-cli-scaffold/EXPERIMENT.md)
- Exp 3 — [Commit-state FSM](experiments/exp-3-fsm/EXPERIMENT.md)
- Exp 4 — [Tape and hooks](experiments/exp-4-tape-hooks/EXPERIMENT.md) (the older [2026-11-07-tape-hooks.md](experiments/2026-11-07-tape-hooks.md) record predates the settled design and is kept as history)

## Scorecard

Per exp and per engine: wall time intent-to-land, context tokens
per Run (provisioning mode noted), human-active minutes,
interventions and repeated explanations, review/rework cycles, and
manual bypasses. Recorded here and in each exp record from Board
data and session usage; unmeasured values are stated, never zero.

## Risks and red chair

- Strongest attack on the goal: "engine" conflates harness,
  topology, and transport. What changed: the contract is defined by
  context provisioning and the report/land ops, not by brand;
  harness and fan-out shape are recorded per Run.
- Strongest attack on order: the baseline was Exp 1 because the
  four-hour bounce was unattributed. The owner killed it — the
  Pi loop was run by hand and convicted directly. The order now
  rests on that first-hand evidence instead of a measurement
  gate. Remaining open: whether watchability's
  loss hides a real debugging need the debug view cannot cover.

## Open questions

1. Exp 1 baseline: killed by the owner, who ran the Pi loop by
   hand and convicted it directly. No measurement gate; the
   Quest proceeds on that evidence.
2. Block/resume versus block-then-respawn. Default: respawn.
   Owner: human, with bp3-mvp-muse-workflows evidence.
3. Reviewer may fix, with a fresh reviewer required — direction
   settled, implementation deferred to a future quest:
   [reviewer-fix icebox entry](../../icebox/2026-11-11-reviewer-fix.md).
   In this Quest, reviewers judge only; fix commits come from
   author Runs.
4. How fat may the engine contract grow before it encodes Pi-pane
   assumptions? Default: no new signal kinds without a second
   engine needing them. Owner: implementer, in Exp 2.
