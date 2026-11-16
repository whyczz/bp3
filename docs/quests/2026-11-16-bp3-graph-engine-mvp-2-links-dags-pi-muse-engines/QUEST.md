---
status: proposed
home_repo: bp3
date: 2026-11-16
---

# 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines

## TL;DR

Three owner-settled changes to the bp3 harness
ecosystem, in dependency order. (1) Every edge
execution claims a magic link first: root worker
mints a one-time link, the child claims it as its
first action, and the claim atomically binds
session-id <> run-id in the common-dir hard store;
bp3 then resolves context from the store and env
vars are demoted to hints. (2) The graph schedules:
ready-set scheduling with per-node timing
measured in-system, wall-clock as a first-class
scorecard field. (3) Last, the rename: graph/node/
state/edge/dep vocabulary, `bp3 g` CLI, and the
conducting skills become the `bp3g` family.

North Star: quality and speed. Tokens may be spent
on validation; wall time may not be wasted on
setup friction or serial waiting. Every speed
claim carries a timer in the system or it is
marketing.

## Terms (settled 2026-11-16, owner)

| Term | Was | Meaning |
|---|---|---|
| graph | quest | the whole work graph; a goal pursued as a graph. CLI door: `bp3 g` (graph create/read/update/delete) |
| node door | (new) | CLI door per noun: `bp3 n` (node read + edge calls). `bp3 g` = graph, `bp3 n` = node, `bp3 harness` = supervisor machinery — one door per noun (owner, red-ink round 1) |
| goal (G) | quest, as owner-facing word | G stands for goal and graph; skills are the `bp3g` family (`/bp3g`) because bare "goal" collides across harnesses |
| node | exp / experiment | one work unit in the graph; root worker dispatches nodes |
| state | FSM state | where a node rests (todo, handed_off, approved, landed, blocked, deleted) |
| edge | transition / engine-fsm-edge | one transition of a node's FSM, executed by exactly one subagent Run |
| dep | depends_on / railway order | a link between nodes; not an edge |
| ready-set | cohort / layer (retired) | nodes whose deps are landed and state is `todo`; dispatched together as a wave, recomputed per read |
| root worker | graph worker / conductor (retired) | the session at the tree's root (depth 0, no parent run); schedules ready-sets, owns human gates |
| link | (new) | one-time claim token binding a session to one edge execution |
| Run | Run | one subagent execution of one edge (unchanged) |
| tape | tape | the harness session recording (unchanged) |

States rest in the root worker's read. Edges are
subagents. A child holds nothing across edges;
context is claimed, never remembered.

Edge names (settled red-ink names round, owner —
option A; rides rename.1, old ledgers keep old
words and the rename table maps them):

| Coded today | Settled name | Caller does |
|---|---|---|
| `submit` | `handoff` | author binds the finished commit |
| `review` | `grade` | reviewer grades the exact commit (`ship\|needs_fix`) |
| `check` | `verify` | machine checks (`pass\|fail`) |
| `land` | `land` | merge into the graph branch |
| state `submitted` | state `handed_off` | verb/state rhyme: `handoff` hands off, node rests `handed_off` |
| `block` | `block` | park for a human decision |
| `resume` | `resume` | human answer re-enters (`BP3_DECIDER=human`) |

Link mint/claim are verbs, not flags:
`bp3 harness link mint --kind node|edge …` and
`bp3 harness link claim <token>`. A node link
carries no edge name — the node worker executes
no transition when it claims.

Door letter settled: `bp3 g`, not `bp3 t`.
Nodes form a DAG (shared deps, diamonds — a tree
allows one parent), scheduled by BFS ready-set
waves; the *execution* is a tree of workers.
Tree survives as a view (`--format tree`) and as
the worker-tree shape, never as the addressed
noun.

## Success picture

A root worker dispatches a node with a one-line
brief: "claim this link, do this edge." The child
claims, works, calls its own edge, dies. Ready
nodes in a ready-set build and grade in parallel
desks; landing is a serial queue. The rollup
shows every node's wall, wait, and dwell time.
The grader joins any tape's session-id to run-id
in one lookup. At the end, everything on live
surfaces — CLI, skills, workflows, records —
speaks graph/node/state/edge and answers to
`bp3 g` and `/bp3g`.

## Scope

| In | Out |
|---|---|
| `bp3 harness link` mint/claim, CAS claim store, by-session index, context resolution; run config replaces InitRecord (`creator:{}`/`claim:{}`/`tape_path`), `record-init` retires, lifecycle fold reads the run config | rewriting landed quests' ledger history text |
| ready-set scheduling, per-node timing derived from ledger + derivations, local thresholds | anything committed for metrics; timing judgments stay in `<git-common-dir>/bp3/` |
| setup timing measured always; optimize only when setup > 3 min (`W_SETUP_SLOW`) | desk pools (killed 2026-11-16; ad hoc desks, measured) |
| generated ASCII/mermaid diagram from live rollup | writing into harness session logs (tapes stay harness-written) |
| rename last: `bp3 g`, `bp3g` skills, graph terms on live surfaces | rewriting landed quests' ledger history text |
| session-id discovery: muse, pi; graceful floor (pid+cwd+window) | adversarial threat model (links are for confused children, not attackers) |

## Timing gates (in-system, local)

- Per node: `wall` (first handoff → land), `wait`
  (create → first handoff), `dwell` per state,
  cycles. Derived from ledger timestamps, shown
  on read, thresholds local, never committed.
- Per Run setup: desk create → first bp3 answer;
  `W_SETUP_SLOW` when > 3 minutes.
- Scorecards report wall minutes AND tokens per
  node. Visibility, not caps.

## Context layer (kubectl pattern, settled red-ink round 1)

One door per noun, nested as the canonical address:
`bp3 g <graph> n <node> e <edge>`. Bare `bp3 e …`
is the claimed shorthand. A context layer resolves
which graph/node an unqualified call means, with
kubectl's precedence — explicit always beats
ambient:

```text
1. nested address in the call     bp3 g G n N e handoff
2. session claim (mvp.1)          by-session index -> claim
3. desk context (cwd)             desk context file from claim
4. nothing                        E_NO_CONTEXT (post-rename)
```

| kubectl | bp3 |
|---|---|
| kubeconfig | claim store in `<git-common-dir>/bp3/` (machine-local, never committed) |
| context | one claim: {graph, node, edge, run-id, session-id, desk} |
| current-context | per-session, never global: parallel children hold different contexts, keyed by session-id, desk as fallback |
| `-n` / explicit flags | the nested `g … n … e …` address; always wins, always printed in verdicts |

`bp3 e` with no edge prints the resolved context
and legal edges. Doors settled (owner, red-ink
round 2): `bp3 g | bp3 n | bp3 e` — one door per
noun, nested address canonical. Configuration
surface: `bp3 config` views the whole store;
bare `bp3 e` is the quick view — resolved context,
its source rung, legal edges, and the config
values in force for that context (thresholds,
desk), so a child can self-diagnose in one call. Context is resolved, never
carried: env vars are hints the layer may
cross-check (`W_CONTEXT_ENV_MISMATCH`), never the
store. This layer is what mvp.2 builds; the doors
above are its surface.

Locked (owner, data round): after claiming, an
edge worker calls only `bp3 e …` — no graph, node,
run-id, or exports — and bp3 resolves the context
from the claim (session rung, then desk rung).
Bare `bp3 e` prints the resolved context, its
source rung, and legal edges. No rung resolving
means refuse `E_NO_CONTEXT` (post-rename), never
a guess at a sibling's context.

## Data (settled red-ink data round, owner)

One canonical record per execution: the **run
config**, keyed by `run_id`, created at
`link mint` — before any worker exists. Claim
completes it; everything else is an index or a
view folded from run configs.

```text
<git-common-dir>/bp3/
  config.json            machine settings ONLY (thresholds, gates)
  runs/<run_id>.json     the run config (canonical, one per Run)
  links/<token_hash>     -> run_id     (written at mint; claim finds its run config by key)
  by-session/<session-id> -> run_id     (derived index, rebuildable)
  desks/<desk>/context   -> run_id      (derived pointer, fallback rung)
  run-lifecycle-derivations/            (existing supervisor fold)
```

Run config shape — facts grouped by who knew
them when. This replaces the supervisor's
InitRecord (settled, functions round, owner):
one birth record per Run, and `record-init`
retires.

```json
{
  "run_id": "2026...-handoff-pi-...-c1",
  "kind": "edge",                    // node | edge
  "graph": "G", "node": "N", "edge": "handoff",
  "state": "claimed",                // minted -> claimed (CAS)
  "desk": ".bp3/worktrees/...",
  "creator": {                       // parent side, known at mint
    "run_id": "...",                 // who minted this Run
    "depth": 2,
    "harness": "pi", "model": "...", "thinking": "high",
    "minted_at": "...", "token_hash": "sha256:..."
  },
  "claim": {                         // worker side, known at claim
    "session_id": "...", "pid": 48151, "cwd": "...",
    "claimed_at": "..."
  },
  "tape_path": "..."                 // supervisor side, at bind-tape
}
```

The lifecycle fold reads this one file: birth
from `creator`, presence from `claim.pid` + tape
mtime, proof from `tape_path`. `bind-tape`
writes `tape_path` into the run config instead
of a derivation row. Node-kind configs carry no
`edge`.

Trees have roots here, as in the supervisor's
derivations: the root worker's run config is the
tree root — `creator.run_id` empty, `depth` 0 —
and every other run config hangs off it through
`creator.run_id`. The supervisor folds a subtree
from its root; cleanup and revival anchor at the
root the same way.

Found, not configured: from any cwd, bp3 runs
`git rev-parse --git-common-dir` (already the
resolution in `harness.ml` and the pi dispatcher)
and appends `bp3/` — one store per repo, shared
by every worktree/desk of that repo. Lookup is
by key: `runs/<run_id>.json` directly, or
session-id -> run_id via the derived index; no
scanning on the hot path. Outside a git repo
there is no store and bp3 refuses — there is
nothing to find.

Stale mints (settled, state round — option C):
a worker that dies between mint and claim leaves
a `minted` run config with no pid to pronounce
orphaned. No TTL: when a graph is done, the graph
worker runs `bp3 harness link cleanup --graph
<graph>` and every still-`minted` run config of
that graph is removed and reported. Claimed run
configs are never touched — their lifecycle is
the supervisor's derived fold, not cleanup's.

Rules: `config.json` never holds contexts — `bp3
config` *views* contexts by folding `runs/`.
Per-session context is just “the run config your
session claimed,” so two edge workers on one node
hold different edges without collision. A run
config is written by bp3 verbs only, never
hand-edited, never committed. Terminal lifecycle
(finished/orphaned) stays derived by the
supervisor fold, not written into the run config.

## Demo (design trace)

One node, end to end — claim to land, then the
same node blocked and revived:

```text
# happy path
root:  bp3 g flappy-graph r
         -> ready-set: [flappy-day, flappy-night]  (one wave)
root:  bp3 harness link mint --kind node --graph flappy-graph --node flappy-day \
         --parent-run-id root-… --depth 1
         -> bp3link_7f3a…   (one-line brief to the node worker)
node:  bp3 harness link claim bp3link_7f3a…        # claimed; session <> node bound
node:  bp3 harness link mint --kind edge … --edge handoff --parent-run-id … --depth 2
edge:  bp3 harness link claim bp3link_91bc…        # claimed; session-id <> run-id
edge:  …builds flappy…
edge:  bp3 e handoff --commit 4fc0cc4 --reason "flappy day variant"
         -> {state: handed_off, run_id: …, source: session claim}
node:  re-reads: handed_off -> mints grade link
edge2: bp3 e grade --verdict ship --reason "artifact + checks verified"
node:  re-reads: approved -> mints land link
edge3: bp3 e land --reason "serial land queue, tip re-checked"
         -> {state: landed}
node:  bubble {node: flappy-day, state: landed} -> root; tree dead

# blocked path (same node, different day)
edge:  …needs a storage choice only the human can make…
         -> typed failure, dies (no bp3 call)
node:  bp3 g flappy-graph n flappy-day e block --reason "choose storage shape"
         -> {state: blocked}; node worker EXITS; tree dead
root:  bubble {node: flappy-day, state: blocked, reason, run chain, inbox key}
         -> human paged (live + inbox); human answers in conversation
root:  BP3_DECIDER=human bp3 g flappy-graph n flappy-day e resume \
         --reason "localStorage, per owner"
         -> fresh node link minted; NEW node worker spawns, re-reads, continues
```

Nothing in either trace parks. Every arrow is a
bp3 verdict or a worker death.

## Worker topology (settled red-ink round 2, owner)

Same logical contract on both harnesses — claim a
link, execute one edge, emit a verdict, die —
different physical shape per harness:

| Layer | Pi | Muse |
|---|---|---|
| root worker | pi session | main session |
| node worker | child pi session (spawn_run) | one workflow run (induct-node script) |
| edge worker | grandchild pi session | agent inside the workflow run |

Pi nests for real: sessions are processes, so a
node-worker session loaded with `bp3-pi` calls
`spawn_run` for its edge workers. Muse flattens:
a workflow cannot launch a workflow and agents
cannot spawn agents, so the node worker is the
workflow script's loop and edge workers are its
agents. Every mint/claim records `parent_run_id`
and depth, so the chain tape→run→node→graph is
one lookup and recursive fan-out stays auditable
and capped. Current Pi wiring does not yet load
the extension into spawned children explicitly;
proving that is part of mvp.1/dogfood.1 scope.

Pi engine MVP v2 tree law: the root Pi session
faces the human and spawns node workers; a node
worker spawns edge workers. Terminal results
bubble edge -> node -> root, then that branch of
the process tree is dead. A node worker may exit
on `blocked` only after all its edge Runs are
terminal in bp3; the root gets one factual bubble
(graph, node, state, reason, last edge, run chain,
desk, inbox key), never a live process to babysit.
Revival after `resume` is a fresh Pi tree with a
new claim/run chain. If the root itself dies, the
next main session revives from bp3 rollup + inbox.

## Worker lifecycle — who does what

Three workers, one rule each: the root worker
schedules, the node worker loops one node's FSM,
the edge worker executes exactly one edge. bp3
holds all state; no worker's memory is load-bearing.

```text
human
  │  answers blocked gates / promotes at graph_fin
  ▼
ROOT WORKER (main session / root pi session)
  │  reads rollup -> ready-set
  │  per ready node: mint node link, spawn node worker
  │  collects terminal bubbles; pages human on blocked
  ▼
NODE WORKER (workflow run / child pi session)   ×N in parallel
  │  claims node link (first action)
  │  loop: read node state -> mint edge link -> spawn edge worker
  │        -> await verdict -> re-read state
  │  exits on landed | blocked | deleted (one terminal bubble)
  ▼
EDGE WORKER (agent / grandchild pi session)     ×1 per edge
     claims edge link (first action)
     does the work (build, grade, land, …)
     calls its own edge via bp3, or returns typed failure
     dies
```

### Root worker

| Phase | Does |
|---|---|
| wake | reads rollup: graph state, ready-set, inbox |
| dispatch | for each ready node: mint node link, spawn one node worker (parallel across the ready-set) |
| collect | awaits terminal bubbles; never reaches inside a live node |
| gate | on `blocked`: page human (live + inbox); on answer, attest + `resume`, then spawn a *fresh* node worker |
| finish | when all nodes are terminal: present scorecard/demo; `graph_fin` promotion is the human's call |

Never does: execute an edge, hold a node's loop,
resume an old worker process.

### Node worker

| Phase | Does |
|---|---|
| claim | first action: claim the node link; context now resolves from bp3, not the brief |
| loop | read node state → choose next legal edge → mint edge link → spawn one edge worker → await its verdict → re-read state |
| ride | `needs_fix` under cycle cap: loop again with the reviewer's named fix verbatim; no human involved |
| replace | edge worker died/orphaned: mint a fresh link, spawn a replacement edge worker |
| exit | exactly one terminal bubble to the root worker: `landed`, `blocked` (with reason + run chain), or `deleted`; on `blocked`, exit only after every spawned edge Run is terminal in bp3 |

Never does: talk to the human, park waiting for an
answer, spawn a second worker for the same edge,
remember state across edges (re-reads bp3 instead).

### Edge worker

| Phase | Does |
|---|---|
| claim | first action: claim the edge link; this binds session-id <> run-id |
| work | the one job the edge names: write code for `handoff`, grade one exact commit, merge for land |
| report | success: call its own edge via bp3 (`bp3 e …`), which stamps the verdict; failure: return a typed failure (code, facts, guidance) immediately |
| die | exits after its verdict/failure; holds nothing for the next edge |

Never does: call a second edge, wait for a human,
mint links for anyone, write proof about itself
(supervisor derives lifecycle from tape + pid).

### Proposed bp3 CLI calls (target spelling)

Target spelling below is post-rename
(`bp3 g | bp3 n | bp3 e`); before rename.1 ships,
the same calls ride today's `bp3 q …` /
`bp3 harness …` equivalents. `bp3 harness link`
and `bp3 config` keep their names.

Root worker calls:

```sh
bp3 g <graph> r                       # rollup: ready-set, inbox, timing
bp3 harness desk prepare <graph> <node> --run <run_id>   # positional, as today
bp3 harness link mint --kind node --graph <graph> --node <node> \
  --parent-run-id <root_run_id> --depth 1 --desk <desk>
# -> returns one-line node link for the node worker's brief
BP3_DECIDER=human bp3 g <graph> n <node> e resume --reason "<human answer>"
bp3 harness link cleanup --graph <graph>   # at graph end: remove its minted leftovers (claimed: never)
bp3 g <graph> r                       # re-read after bubbles; scorecard at graph_fin
```

Node worker calls:

```sh
bp3 harness link claim <node_link>          # FIRST ACTION: claim; binds session/workflow <> node
bp3 g <graph> n <node> r              # read own node (canonical address)
bp3 n r                               # same read via claimed shorthand
bp3 harness link mint --kind edge --graph <graph> --node <node> --edge <edge> \
  --parent-run-id <node_run_id> --depth 2 --desk <desk>
# -> returns one-line edge link for the edge worker's brief
bp3 harness watch --run-id <edge_run_id>   # await/disposition a dead edge Run
bp3 g <graph> n <node> e block --reason "<specific reason>"   # human required; then EXIT
bp3 config --source                   # debug only: why context resolved this way
```

Edge worker calls (exactly these, then dies):

```sh
bp3 harness link claim <edge_link>          # FIRST ACTION: claim; binds session-id <> run-id
bp3 e                                 # self-diagnosis: context, source rung, legal edges
bp3 e handoff --commit <sha> --reason "<what changed>"        # build edge
bp3 e grade --verdict ship|needs_fix --reason "<grade>"     # grade edge (binds the recorded commit)
bp3 e verify --verdict pass|fail --reason "<evidence>"        # verify edge, where the node has one
bp3 e land --reason "<why this lands>"                       # land edge
# canonical equivalents: bp3 g <graph> n <node> e handoff|grade|land …
# failure path: NO bp3 call — return typed failure to the node worker, die
```

Supervisor-side calls (workflow script / pi
dispatcher only — never the edge worker):

```sh
bp3 harness bind-tape --run-id <run_id> --tape-path <tape>   # after child exit
bp3 harness watch --run-id <run_id>                          # sole killer / orphan disposition
bp3 harness find-tape --run-id <run_id>                      # grader join: run -> tape
bp3 harness find-tape --session-id <session_id>              # grader join: session -> run
```

No other bp3 calls are part of a worker's job.
In particular: edge workers never call
`record-init`, `bind-tape`, or `block`; node
workers never call `resume`; only the root
worker calls `resume`, and only with
`BP3_DECIDER=human` from the human's actual words.

### Lifecycle walk (one node, happy path + one block)

```python
# root worker
for node in ready_set(graph):
    spawn_node_worker(mint(node=node, by=root))     # parallel
bubble = await_any()
if bubble.state == "blocked":
    page_human(bubble); answer = human_input()
    bp3.resume(bubble.node, answer, decider="human")
    spawn_node_worker(mint(node=bubble.node))       # fresh tree, new claim

# node worker
ctx = claim(node_link)                              # first action
while (s := bp3.read(ctx.node)).state not in TERMINAL:
    r = spawn_edge_worker(mint(node=ctx.node, edge=next_edge(s),
                               parent_run_id=ctx.run_id))
    if r.failed and r.needs_human:
        bp3.block(reason=r.reason); return bubble("blocked", r)
    # else: verdict already moved state; loop re-reads
return bubble(s.state)

# edge worker
ctx = claim(edge_link)                              # first action
result = do_work(ctx)                               # build / grade / land
bp3.call_edge(ctx, result) if result.ok else fail_fast(result)
# die
```

The tree dies with every bubble: edge worker after
its edge, node worker after its terminal bubble.
Revival is always a fresh spawn from bp3 state —
the root worker (or a new main session, reading
rollup + inbox) re-mints and re-spawns; nothing is
ever resumed in place.

## Deliberately open (explored in-graph)

Not pre-decided; each is measured or decided by
its owning node during the graph, from evidence:

| Question | Explored by | How it closes |
|---|---|---|
| session-id exposure per harness — which resolution rung do muse/pi claims actually land on? | dogfood.1 | measured rung distribution in the A/B drive; a third rung is designed only if session+desk both fail routinely |
| dep freeze rule — may deps change after a node leaves `todo`? | mvp.3 | scheduler built with deps mutable-but-logged; anomalies (or their absence) in dogfood.2 propose the freeze rule to the root worker |
| Pi extension loading into spawned children — does a child pi session get `bp3-pi` tools without explicit loading? | mvp.1, proven in dogfood.1 | nested Pi claim drive either passes as-is or mvp.1 adds explicit extension loading to the spawn |

## Human touchpoints

- Blocked gates only, per root-worker rails.
- graph_fin promotion — owner, after demo.

## Fail-fast and blocked handling (settled red-ink round 2, owner)

Failure is a state transition, never a waiting
process. Workers fail fast: complete the edge,
return a typed failure, or exit through `block`.
No worker parks, polls for the human, retries
forever, or carries the decision in memory.

Blocked is a node state, not a parked process:

```text
edge worker fails / needs a decision
  -> node worker calls `block` (commits WIP iff the
     human needs the diff to decide), returns blocked
  -> node workflow EXITS; nothing waits or parks
  -> root worker pages the human (live + inbox)
  -> human answers in conversation; root worker
     attests BP3_DECIDER=human, calls `resume`
  -> root worker relaunches induct-node for that node;
     it re-reads state and continues
```

`needs_fix` under the cycle cap never blocks: the
node worker rides it, carrying the reviewer's named
fix verbatim. Exceeding the cap escalates to
blocked. A blocked node starves only its
dependents; the rest of the ready-set keeps moving.
Workers are cattle: blocked kills the run, and the
ledger — never the dead worker's memory — is what
the relaunch resumes from.

The entire worker tree dies with the bubble. On
Pi: edge session terminates, node session records
`blocked` and exits, root main session receives
the facts and can revive the node after `resume`
by spawning a fresh tree. On Muse: all agents in
the node workflow return, the workflow exits, and
revival launches a fresh workflow. The human can
revive from the root because bp3 — not any worker
process — holds the node, reason, run chain, and
next legal move.

## Exps

Exp display names are `<milestone>.<number> - <slug>`.
Folders and bp3 exp IDs use the dotless spelling
`exp-<milestone>-<number>-<slug>`.

### Milestone: migration — words first

### mig.1 - handoff-verbs — [record](experiments/exp-mig-1-handoff-verbs/EXPERIMENT.md)
First node. FSM verbs/state take settled names
(`submit -> handoff`, `review -> grade`,
`check -> verify`, `submitted -> handed_off`) in
code, workflow briefs, and tests. Old quest files
never move; the fold maps old ledger strings on
read, new lines write new words.

### mig.2 - traverse-rename — [record](experiments/exp-mig-2-traverse-rename/EXPERIMENT.md)
Conducting skills take graph names early:
`/induct` + `/induct-quest` -> `/traverse`,
`/induct-quest-no-human` -> `/traverse-no-human`,
and the `induct-exp` workflow becomes `node-loop`
(the node worker's loop; mvp.3 generalizes it).

### Milestone: config — the local store

### config.1 - bp3-config — [record](experiments/exp-config-1-bp3-config/EXPERIMENT.md)
The machine-local hard store, named: `bp3 config`
tree under the git common dir (contexts, desks,
local thresholds, claims, by-session index,
derivations). Written only by bp3 verbs, viewed
via `bp3 config`, never committed, zero setup.

### Milestone: mvp — link, context, schedule, diagram

### mvp.1 - link-claim — [record](experiments/exp-mvp-1-link-claim/EXPERIMENT.md)
`bp3 harness link`: mint a one-time link for one
edge execution; child claims as first action. CAS
in the common-dir store (one winner,
`E_LINK_SPENT` names the first claimant). Claim
records caller facts and the by-session index.

### mvp.2 - context-resolution — [record](experiments/exp-mvp-2-context-resolution/EXPERIMENT.md)
bp3 resolves graph/node/edge/run from the claim
store (session, then desk) and stamps verdicts
and ledger lines. No env ritual, no retyped
context. Env is a hint only.

### mvp.3 - ready-set-timing — [record](experiments/exp-mvp-3-ready-set-timing/EXPERIMENT.md)
BFS ready-set waves from node deps; rollup emits ready
nodes and per-node wall/wait/dwell; setup timing
per Run with the 3-minute `W_SETUP_SLOW` gate.
Parallel build/grade in per-node desks, serial
land queue semantics stated and readied. Named
deliverable: `induct-node` — one workflow run per
node owning the whole FSM loop (the old
induct-exp / induct-grade / quest-land become
phases inside it); the root worker dispatches
ready-set waves and handles blocked + graph_fin only.

### mvp.4 - diagram-emit — [record](experiments/exp-mvp-4-diagram-emit/EXPERIMENT.md)
Generated ASCII + mermaid from a live rollup:
nodes with state/cycle, deps as ready-set waves, blocked
nodes naming what they starve.

### mvp.5 - blocked-fail-fast — [record](experiments/exp-mvp-5-blocked-fail-fast/EXPERIMENT.md)
No parked workers. An edge worker completes its
edge or fails it immediately; the node worker
records the decision point through `block` and
exits when a human is required. `needs_fix` below
the cycle cap rides automatically, a dead edge
worker is replaced from derived `orphaned`, and a
fresh node worker resumes from bp3 after `resume`.

### Milestone: dogfood — use it ourselves

### dogfood.1 - link-drive — [record](experiments/exp-dogfood-1-link-drive/EXPERIMENT.md)
A/B proof on the flappy node: old brief vs link
brief on both harnesses, seeded setup attacks
refusing at claim. Metrics are the acceptance.

### dogfood.2 - parallel-drive — [record](experiments/exp-dogfood-2-parallel-drive/EXPERIMENT.md)
Two independent flappy-variant nodes, one ready-set,
parallel desks, parallel build+grade, serial
land. Scorecard: wall and tokens per node.

### Milestone: rename — migrate everything, last

### rename.1 - bp3g-rename — [record](experiments/exp-rename-1-bp3g-rename/EXPERIMENT.md)
Full rename on live surfaces: `bp3 g` CLI door,
graph/node/state/edge/dep vocabulary, skills
become the `bp3g` family (`/bp3g` conducts,
`bp3g` variants for framing/no-human), launcher
workflows, templates. (Edge verbs and the
`submitted -> handed_off` state already migrated
in mig.1; this node is nouns, doors, and skills.)
The rename table in Terms is the
mapping, and every live surface takes the new
verbs in this one change. Old terms grep to zero
on live surfaces; landed ledger text is history
and keeps the old edge words.

### Milestone: landing

### landing.1 - landing-wrapup — [record](experiments/exp-landing-1-landing-wrapup/EXPERIMENT.md)
Scorecard (timing included), findings
disposition, landing walkthrough actually run
(red-ink-quest-landing-demo diligence), for the
owner's promotion review.

## Scorecard

Fields: claims observed (minted/claimed/spent),
context resolutions, per-node wall/wait/dwell,
setup wall per Run, ready-set wall vs serial estimate,
tokens per node, drives observed per harness,
human-active minutes — or "unmeasured", never zero.

## Exp diagram

```text
mig.1 ──────────────┐ (verbs first; everything after speaks handoff/grade)
config.1 ─► mvp.1 ─► mvp.2 ─┬─► mvp.3 ─► mvp.4
                            ├─► mvp.5 ────────┐
                            └─► dogfood.1 ─► dogfood.2 ─► rename.1 ─► landing.1
                                              ▲
                            mvp.3 ────────────┘ (and mvp.5, dogfood.1 feed it)

ready-set waves: [mig.1, config.1] -> [mig.2, mvp.1] -> [mvp.2] -> [mvp.3, dogfood.1]
         -> [mvp.4, mvp.5] -> [dogfood.2] -> [rename.1] -> [landing.1]
rename.1 = nouns/doors/skills only; verbs already migrated in mig.1
```
