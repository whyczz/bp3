---
name: bp3g
description: Conduct one bp3 graph from the main session — read state with bp3 g r, dispatch the one step that state calls for, re-read, until the graph is terminal or a human decision is owed.
---

# Bp3g

Use when a human in a bp3-enabled repo invokes this skill by
name (`/bp3g <graph>`, `$bp3g <graph>`) or asks to "bp3g",
"run", or "keep going on" a named graph until it lands or
blocks. One graph per bp3g. One output: step dispatches
through `bp3 g`, ending in a bp3g report — what reached
`node_fin`, what is blocked, and what human decision is owed
next. Finish lines have report words: `node_fin` names an node
whose state is `landed` (its `land` edge taken); `graph_fin`
names graph promotion to master, the only owner-gated finish
line. The FSM states stay `landed`; `node_fin`/`graph_fin`
name the finish lines in reports, never new edges.

Use `graph` instead to frame a new graph. Use `using-bp3`
instead for a single state operation by hand (one handoff, one
grade, recovery after a dead session). Use
`red-ink-bp3g-landing-demo` instead when the graph is done and the
human wants the landing writeup. A design under review is
`red-ink`'s job, not a bp3g.

## Conductor rule

This skill is the conductor: it owns the loop and nothing
else. It reads state, dispatches the one step the state calls
for, and re-reads. It never does a step's work itself, never
calls a verdict edge for a step, and never re-judges a grade
matrix — it quotes the matrix verbatim. Legality is `bp3 g`'s
call, never this skill's: a refusal is information, answered by
re-reading, not by arguing or retrying unchanged.

Cycles are weather; blocks are decisions. A `needs_fix`
verdict below the cycle cap is weather: the conductor rides
it (Procedure step 3) without paging the owner. `blocked` is
the only page: it means a decision only a human can make is
owed. Fake blocks train rubber-stamps; never manufacture one
out of a cycle.

## No-human variant

With no human present, the `bp3g-no-human` skill
runs this same conductor over a queue of graphs under
no-human rails: preflight before queueing, desks only,
blocked work parks in the inbox instead of paging, a
stated Run budget stops the queue, and the run ends in
the dawn report. No-human never attests (`BP3_DECIDER`
stays unset), never takes `resume` or `delete`, and
never promotes — `graph_fin` stays the owner gate. The
rails live in `skills/bp3g-no-human/SKILL.md`;
this section names the variant only, so the procedure
above stays the one conductor procedure.

## Procedure

1. Take exactly one argument: the graph. Confirm the engine
   exists: `bp3 g r <graph>` must answer JSON. If `bp3 g` is
   unavailable, stop and say so — never improvise state with
   file edits or another command.
2. Read the world live: `bp3 g r <graph>` gives node states,
   the railway order, and the blocked inbox. Trust only this
   read — never session memory, `state.yaml`, or a ledger read
   by hand. At a fan-out group, stop and ask the human which
   members run; members are exploration only and never
   landable.
2.5. Graph worktree, by default: before the first dispatch,
   `./bin/bp3 harness desk prepare --graph <graph>` and pass its
   `path` as `desk` in every step's args. All step children
   work in that one worktree for the whole graph; the
   conductor's checkout is never worked in, so parallel
   bp3gs and the owner's own work cannot collide with the
   Run. If the desk cannot be prepared, stop and say so —
   never fall back to the shared tree. Release it only at
   `graph_fin` or on the owner's word (`bp3 harness desk
   release --graph <graph>`; a dirty desk refuses and is
   preserved).
3. Dispatch exactly one step per read, by state only:

   | State | Dispatch | Args |
   |---|---|---|
   | `todo` | `node-loop` workflow | `{graph, node, ts, harness, model, desk}` |
   | `handed_off` | `bp3g-grade` workflow | `{graph, node, ts, harness, model, commit, desk}` with `commit` from this read |
   | `approved` | `bp3g-land` workflow | `{graph, node, ts, harness, model, desk}` |
   | `blocked` | human gate (step 4) | — |
   | `landed` / `deleted` | none | advance to the next node, or report at terminal (`landed` is reported as `node_fin`) |

   Ready-set dispatch (mvp.3): the rollup read reports
   `ready_set_waves`, `ready`, `starved`, per-node `deps`
   and `timing` (wall/wait/dwell derived from ledger
   timestamps), and per-Run `setup` (`W_SETUP_SLOW` when a
   setup exceeds the local threshold). Dispatch one
   `bp3g-node` workflow run per node in `ready`, in
   parallel desks: it owns that node's whole FSM loop
   (author, grade+verify, and land as phases inside it)
   and returns exactly one terminal outcome (`landed`,
   `blocked`, or `deleted`). The state-step workflows in
   the table above remain the phases' shapes and the
   fallback when `bp3g-node` is not installed. Landing
   stays serial: one node's land at a time, each land
   re-checked against the new graph tip. A blocked node
   starves only the dependents named in `starved`; the
   rest of the ready set keeps moving.

   Fail-fast inside the node run (mvp.5): an edge worker
   completes its edge, returns a typed failure, or dies.
   A typed failure makes the node run record the decision
   point through `block` once — the failure's reason
   verbatim — and exit; the failed edge is never retried
   and no worker parks or polls for the human. A worker
   that dies with no verdict is an orphaned Run: the node
   is not blocked, and the run mints one fresh link and
   dispatches one replacement. The run returns exactly
   one terminal bubble carrying facts only (graph, node,
   state, reason, last edge, run chain, desk, inbox
   key); the conductor pages the human off that bubble,
   and revival after `resume` is a fresh node run that
   re-reads bp3 — no worker process is ever resumed.

   `ts` is a UTC compact timestamp (for example
   `20261107T143022Z`) supplied in args because workflow
   scripts cannot read the clock; `harness` and `model` carry
   this session's identity (`muse-code` and its model),
   because workflow children do not inherit the launching
   session's env. Steps are installed with this skill by
   `bp3 skills install`; if a named step is missing, stop and
   say so rather than improvising children. Grade replay is
   free: re-dispatching `bp3g-grade` on the same `commit`
   is always safe, so a killed grade is simply dispatched
   again — no attempt bookkeeping here.

   Grade evidence contract (followup.1): inside
   `bp3g-grade`, a deterministic grade validations
   pipeline mints every adherence row in code before the
   audit child spawns (empty stdout quoted as
   `(empty stdout, exit 0)`, never hand-quoted); the audit
   builds only acceptance rows. A row without typed
   evidence is re-collected once inside the audit (named
   rows) and never reaches the FSM: it casts no verdict,
   burns no author cycle, and pages no human. Evidence
   still uncollectable returns outcome `audit_failure`,
   naming the row and the collection error — quote it as
   grader paperwork, never as a product `needs_fix`, and
   simply re-dispatch the grade. When grade and verify
   cast in parallel and the second cast is refused with
   `E_ILLEGAL_EDGE` after the first moved state, the
   outcome names it an expected verdict race; re-read and
   judge from the fresh state.

   Cycle autonomy: when a grade returns `needs_fix` (or a
   verify returns `fail`) and the re-read shows the node back
   in `todo` below the cycle cap, the conductor dispatches
   the next author cycle itself, carrying the grader's
   named fix — including any regression test or acceptance
   amendment that fix demands — in the next dispatch's
   context. It does not ask the owner about the cycle, does
   not wait for an owner answer, and does not present the
   cycle as a decision. The named fix rides along verbatim;
   the conductor never re-judges it, widens it, or drops it.
   It keeps dispatching grade → author → grade until the node
   leaves the cycle (`landed`, `blocked`, or `deleted`) or
   the cap is hit. When the re-read shows the cycle cap
   reached (the node in `blocked` at the cap), the conductor
   stops looping and escalates to the owner through the
   blocked gate instead of dispatching another cycle.
4. Blocked gate (the only page): present the inbox in the
   main session (node, reason, checkpoint, cycle), capture
   the human's decision in their words, attest it
   (`BP3_DECIDER=human`), and take `resume` or `delete`
   through `bp3 g <graph> u <node>`. The human never calls bp3
   and never supplies a commit. A blocked Run is never
   resumed in place; after a `resume`, the next read
   dispatches a fresh step. Only human-only calls reach
   this gate: scope changes, `delete`, and moves touching
   another graph's state. The conductor never takes a
   `delete` or a scope change autonomously, at any cycle.
5. Re-read after every dispatch return (`bp3 g r <graph>`)
   and go to step 3. A return that moved nothing (refusal, no
   commit) is re-judged from the fresh read, never retried
   unchanged against a moved tip.
6. Stop when the rollup is terminal (every node `landed` or
   `deleted`) or a human decision is owed that this session
   cannot get. Name each `landed` node `node_fin` in the
   report; when the graph is promoted to master, name that
   finish line `graph_fin` (owner gate, demo first). Report: dispatches per node with their ledger
   evidence, the grade matrices quoted verbatim, Runs and
   tapes left behind, scorecard fields (wall time, context
   tokens, human-active minutes — or "unmeasured", never
   zero), and the next decision owed.

## Rules

- The skill writes no state. `bp3 g u` is the only writer,
  called by step children (and at the blocked gate, by this
  session on attested human words); ledger files, `state.yaml`,
  and branch tips are never hand-edited, and tape is evidence,
  never parsed into facts.
- Human attestation comes only from actual human words in
  this session. The engine never attests on the human's
  behalf, and `resume` without it is refused
  (`E_HUMAN_REQUIRED`) — that refusal is the gate working.
  Attestation is owed at the blocked gate only; a
  `needs_fix` cycle below the cap needs no attestation,
  because no human decision is being recorded.
- Identity rides env (`BP3_HARNESS`, `BP3_MODEL`) set per Run
  by the launcher or hooks. Unset means `unknown` plus a
  warning in the verdict; never guess a model name.
- Verdicts bind the exact commit reviewed. A verdict naming a
  superseded commit is refused; dispatch a fresh step against
  the current commit instead of arguing with the refusal.
- Instructions only: this skill holds no state, spawns no
  daemon, and assumes no runtime beyond the main session, its
  workflow children, and the `bp3 g` binary.
