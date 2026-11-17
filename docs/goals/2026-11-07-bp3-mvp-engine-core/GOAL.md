---
status: landed
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
- Induct: one engine loop over a quest — read the railway and
  inbox, dispatch Runs for the next legal edges, autoland at
  `approved`, and stop only when the rollup is terminal or a
  human decision is owed (`blocked`, a fan-out choice). A
  induct is a session of work, not an edge: many Runs, one
  induct. Recovery from a dead induct is a fresh induct, never a
  resumed one.
- Induct-exp: the saved Muse workflow `induct` launches
  for one exp. From mathematical induction: take the exp's
  current state as true, apply one legal step, re-read the
  state, and repeat. Base cases (exits): the state is
  `landed`, `blocked`, or `deleted`, so it returns to
  `induct`; a step that changes nothing (refusals, no commit)
  also exits as `refused` for `induct` to re-judge. It loops
  the exp's inner FSM; it does not navigate the quest railway.
- Tree view: the human read of a quest or exp
  (`bp3 q r --format tree`), the presentation /quest and
  red-ink show the owner. Exp markers: `+` todo, `u`
  submitted/approved/blocked, `-` deleted, blank landed
  (clean, like git status). Each exp also carries its
  proposed file changes — `+` added, `u` updated, `-`
  deleted, from the bound commit's diff — so wrong files are
  spotted up front, before land. Unsure (nothing bound, or
  the diff cannot be read) is `?`, never an empty list.
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
- `goal_type`: the outer plan (knobs only, from `plans/`).
- `exp_type`: an exp's inner profile (FSM knobs, required
  checks, skill names).
- Engine: the bp3 FSM plus a harness — the whole
  execution system that takes edges and runs work.
- Harness: the third-party app host and its bundle —
  model, skills, hooks, and extensions (e.g. Muse
  Code, Codex). Harness and model are recorded per
  ledger line.

## Demos (observed 2026-11-12 — the binary exists; these ran)

```text
HAPPY PATH (this quest's own exps, driven through bp3 q)
  exp-2..exp-5: todo --submit--> submitted --review ship + check pass-->
  approved --land--> landed        (rollup: landed, inbox: [])

BLOCKED RAILWAY (toy-drive/blocked-demo)
  submitted --needs_fix @ max_cycles--> blocked  [human_action_required]
  bp3 q r toy-drive -> inbox: [{exp: blocked-demo, reason, cycle, since}]
  resume without BP3_DECIDER=human -> E_HUMAN_REQUIRED (exit 1)
  resume as human -> todo c2 -> submit -> ship+pass -> landed

LLM MISFIRE (observed on exp-2 before its submit)
  todo + land -> E_ILLEGAL_EDGE {state: todo, legal_edges:
  [submit, block, delete]}   state unchanged, nothing ledgered

FINAL HUMAN VIEW (bp3 q r <quest> --format tree, observed)
  2026-11-07-bp3-mvp-engine-core [proposed] rollup: landed
  ├──   exp-2-cli-scaffold - landed, cycle 1, commit 4d9ceaa  [+3 u4 -1]
  │   ├── u Makefile
  │   ├── bin
  │   │   └── u bp3
  │   ├── invoke
  │   │   ├── + dune
  │   │   └── + main.ml
  │   ├── plans
  │   │   ├── u default.yaml
  │   │   └── u direct.yaml
  │   └── test
  │       ├── - invoke.sh
  │       └── + q.sh
  ├──   exp-3-fsm - landed, cycle 1, commit 4d9ceaa  [+3 u4 -1]
  │   └── (same changeset as exp-2: the FSM rides the core commit)
  ├──   exp-4-tape-hooks - landed, cycle 1, commit a43bcd6  [+3 u5 -0]
  │   ├── .agents
  │   │   ├── skills/induct/SKILL.md (u)
  │   │   └── workflows/induct-exp.js (+)
  │   ├── .claude, .pi (same induct renders, u)
  │   ├── skills
  │   │   └── induct
  │   │       ├── u SKILL.md
  │   │       └── workflows
  │   │           └── + induct-exp.js
  │   └── test
  │       ├── u skills.sh
  │       └── + tape.sh
  └──   exp-5-muse-engine - landed, cycle 1, commit a43bcd6  [+3 u5 -0]
      └── (same changeset as exp-4: the engine commit)
  (tree(1) style, per directory: quest is the root, exps are
   branches, proposed files expand by directory as leaves;
   markers + todo/added, u in-flight/updated, - deleted,
   blank landed, ? unsure; per-exp view adds legal edges:
   bp3 q <quest> r <exp> --format tree)

LIVE ENGINE (toy-drive/parser-fix via induct-exp, observed)
  induct-exp children took submit/review/check/land; outcome: landed
  ledger: 5 lines on bp3/exp/toy-drive/parser-fix, verdicts on the
  exact commit; tape+notes on the quest branch for the submit Run
  first live attempt refused: workflow args arrive as a JSON string
  (script now parses both); children first recorded unknown/unknown
  identity (env now passed explicitly in args)
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
[bp3 MVP: the loop on itself](../2026-11-05-bp3-mvp/GOAL.md) proved the
Board, brief/report ops, and gated landing, but its center bet —
fresh-context Workers in watched Zellij panes — makes every Run
re-buy its context. Four-hour coder/reviewer bounces were observed;
the human judges watchability and takeover to be comfort, speed the
requirement. This Quest keeps the proven record and landing layers
and rebuilds only how work executes.

## Success picture

The founding evidence is the owner's: the predecessor loop
was run by hand and it sucks — no baseline exp is run. The
engine contract is specified; the commit-state machine runs the toy exp end to end — submit,
review, check, CAS land — with guards intact. The Muse engine
(Exp 5) runs that machine end to end on workflow children and
dogfoods this quest's own build; the separate Muse executor
quest was deleted (2026-11-11) and folded in here.
Landing is recorded here with the
measured context cost per edge, and limitations. Record layer as
decided after red chair: no SQLite Board — bookkeeping lives in
files in git: per-exp ledgers are the record, quest state is a
rollup, and `state.yaml` files are derived caches, written only
through `bp3 q <quest> u <exp>`. First slice landed as
`bp3 invoke` (rename owed in one change:
binary, tests, docs, skills) with the `default` goal_type
(one review round) and fixture tests in `test/invoke.sh`.

### Landing record (2026-11-14, owner-promoted)

All six exps landed through `bp3 q` (rollup `landed`, inbox
empty): exp-2 CLI scaffold, exp-3 FSM, exp-4 tape/hooks
(design), exp-5 Muse engine, exp-6 hooks emitter, exp-7 live
hooks evidence. Diligence gate (red-ink-goal-landing-demo)
passed on re-run after option A closed the live-evidence gap.

Measured: exp-7 cycle-2 Runs recorded `usage_recorded` in
their own ledgers — input tokens 6,855,377 / 1,580,906 /
536,551 / 426,108 per Run (submit/review/check/land), wall
80s for the submit Run; tape + hook facts are committed on
exp branches. Human-active minutes: unmeasured, never zeroed
(one `resume` decision on exp-6, one on exp-7, plus gates).

Limitations, stated plainly: Claude Code-side hook firing is
fixture-asserted only (no Claude Code harness driven here);
`--format table` is still key:value lines; no OCaml unit
tests under the shell fixtures. The last two are frozen with
triggers in `docs/icebox/2026-11-14-bp3-cli-small-fixes.md`
and `docs/icebox/2026-11-14-bp3-ocaml-unit-tests.md`.
Operational lesson recorded in Exp 7: Muse loads hooks
at session start — hook-dependent workflows must launch from
a process started after `.muse/hooks.json` exists.

## Scope

In: the `bp3 q` CLI
scaffold; the commit-state FSM (states, edges, guards,
YAML goal_type plans); and the Muse engine (Exp 5:
the `induct` skill, `induct-exp`, Muse hooks) that dogfoods the
railway.
Inherited by reference: the canceled Quest's Exp 2
auto-land kernel candidate `9e1b1d0` and its gated-landing
contract. The former Muse executor
quest (bp3-mvp-muse-workflows) was deleted 2026-11-11; its
executor test is Exp 5 here.
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
| 5 — Muse engine | The dogfood engine: `induct` skill + `induct-exp` workflow + Muse hooks driving the railway | Toy exp travels `todo → landed` on workflow children; forced `blocked` bubbles to the main session and resumes on the human's word | Exp 2 + Exp 3 + Exp 4 |

Records:

- Exp 1 — Timed baseline: **killed by the owner** (ran the
  predecessor loop by hand; it sucks — measurement unnecessary). Record kept
  as a fossil: [exp-1-baseline](experiments/exp-1-baseline/EXPERIMENT.md)
- Exp 2 — [CLI scaffold: u, discover, CRUD](experiments/exp-2-cli-scaffold/EXPERIMENT.md)
- Exp 3 — [Commit-state FSM](experiments/exp-3-fsm/EXPERIMENT.md)
- Exp 4 — [Tape and hooks](experiments/exp-4-tape-hooks/EXPERIMENT.md) (the older [2026-11-07-tape-hooks.md](experiments/2026-11-07-tape-hooks.md) record predates the settled design and is kept as history)
- Exp 5 — [Muse engine](experiments/exp-5-muse-engine/EXPERIMENT.md) (pulled into this quest for dogfooding from the deleted downstream quest)

## Scorecard

Per exp and per engine: wall time intent-to-land, context tokens
per Run (provisioning mode noted), human-active minutes,
interventions and repeated explanations, review/rework cycles, and
manual bypasses. Recorded here and in each exp record from Board
data and session usage; unmeasured values are stated, never zero.

Observed 2026-11-12 (this quest's own drive): four exps landed
through bp3 q, one ledger line per accepted transition, zero
manual state edits. Toy live run: parser-fix submit-to-land in
about three minutes of wall time (ledger timestamps). Context
tokens per Run and human-active minutes: unmeasured. Two
dogfood defects found and fixed in flight (dune artifacts vs
the dirty-tree guard; workflow args as JSON string; a third,
unknown child identity, is fixed in induct-exp and awaits its
next live run for confirmation).

## Risks and red chair

- Strongest attack on the goal: "engine" conflates harness,
  topology, and transport. What changed: the contract is defined by
  context provisioning and the report/land ops, not by brand;
  harness and fan-out shape are recorded per Run.
- Strongest attack on order: the baseline was Exp 1 because the
  four-hour bounce was unattributed. The owner killed it — the
  predecessor loop was run by hand and convicted directly. The order now
  rests on that first-hand evidence instead of a measurement
  gate. Remaining open: whether watchability's
  loss hides a real debugging need the debug view cannot cover.

## Open questions

1. Exp 1 baseline: killed by the owner, who ran the predecessor
   loop by hand and convicted it directly. No measurement gate; the
   Quest proceeds on that evidence.
2. Block/resume versus block-then-respawn. Default: respawn.
   Owner: human, with Exp 5 evidence.
3. Reviewer may fix, with a fresh reviewer required — direction
   settled, implementation deferred to a future quest:
   [reviewer-fix icebox entry](../../icebox/2026-11-11-reviewer-fix.md).
   In this Quest, reviewers judge only; fix commits come from
   author Runs.
4. How fat may the engine contract grow before it encodes one
   harness's pane assumptions? Default: no new signal kinds without a second
   engine needing them. Owner: implementer, in Exp 2.
