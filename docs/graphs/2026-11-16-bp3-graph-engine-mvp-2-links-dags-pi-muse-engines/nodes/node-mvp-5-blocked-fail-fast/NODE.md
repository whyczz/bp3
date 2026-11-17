---
date: 2026-11-16
goal: ../GRAPH.md
exp: mvp.5
status: proposed
---

# mvp.5 - blocked-fail-fast: no parked workers

## TL;DR

Failure is a state transition, never a waiting
process. An edge worker either completes its one
edge or fails it immediately and returns a typed
failure. The node worker records the outcome,
calls `block` when a human decision is required,
and exits. It does not park, poll for the human,
retry forever, or preserve hidden conversational
state. The conductor pages the human, records the
answer through `resume`, and launches a fresh node
worker that reconstructs the next move from bp3.

`needs_fix` below the cycle cap is not blocked:
the node worker rides it automatically with the
reviewer's named fix verbatim. A dead edge worker
is not blocked either: its Run is derived
`orphaned`, and the node worker mints a fresh link
and dispatches a replacement edge worker.

## Demo (design trace)

```text
node N: todo -> handed_off -> grade = needs human choice
node worker: bp3 e block --reason "choose storage shape"
node worker: exits {state: blocked, node: N, reason: ...}
conductor:   inbox + live page -> human answers -> bp3 e resume
conductor:   launches fresh node worker -> reads N -> continues

node M: review = needs_fix (cycle 1 of cap)
node worker: stays alive, dispatches fix edge, no human page

node O: edge worker process dies before verdict
supervisor:  Run lifecycle derived orphaned
node worker: mints replacement link, dispatches one new edge worker
```

## Diagram

```text
edge worker
  |-- success ---> verdict ---> node worker continues FSM loop
  |
  |-- typed failure ------------------------------+
  |-- needs_fix under cap -> fix edge ------------+
  |-- dead / silent -> derived orphan -> replace-+
                                                  v
                                           node worker decides
                                                  |
                    +-----------------------------+----------------+
                    |                                              |
                    v                                              v
             continue / retry once                         human required
             inside FSM law                                      |
                                                                 v
                                                    bp3 e block + reason
                                                                 |
                                                                 v
                                                  node worker exits now
                                                                 |
                                                                 v
                                           conductor pages human (live + inbox)
                                                                 |
                                                                 v
                                           human answer -> bp3 e resume
                                                                 |
                                                                 v
                                           fresh node worker re-reads bp3
```

## Pseudocode

```python
def run_node(node_id):
    claim_node_context()

    while True:
        node = bp3.read_node(node_id)  # never trust memory
        if node.state in {"landed", "deleted"}:
            return node.state
        if node.state == "blocked":
            return blocked(node)       # a fresh launch may follow resume

        edge = next_legal_edge(node)
        link = bp3.link.mint(node=node_id, edge=edge,
                             parent_run_id=current_run_id())
        result = dispatch_one_edge_worker(link)  # exactly one Run

        if result.ok:
            continue                   # verdict already changed bp3 state

        if result.kind == "needs_fix" and node.cycle < cycle_cap(node):
            continue                   # named fix rides the next loop

        if result.kind == "orphaned":
            continue                   # next loop mints a replacement link

        bp3.edge("block", reason=result.reason,
                 commit_wip=result.needs_human_to_see_diff)
        return blocked(node_id, result.reason)


def conductor(graph):
    outcomes = launch_ready_nodes(graph)
    for outcome in outcomes:
        if outcome.state == "blocked":
            page_human_once(outcome.node, outcome.reason)
    # No conductor or node-worker process waits on the human.
```

| Field | Value |
|---|---|
| Intent | fail immediately, preserve the decision point in bp3, and spend zero worker context while waiting for a human |
| Lane | standard |
| Output | typed edge failure, blocked verdict/reason, one conductor page plus inbox record, fresh worker launch after `resume` |
| Depends on | mvp.2 context resolution; mvp.3 `induct-node` scheduler/worker loop |
| Worker rule | blocked exits the node worker; it never sleeps, parks, polls, or retries the human gate |

## Pi engine MVP v2: the whole tree dies

Pi gets the recursive form of the same law. The
root Pi session is the root worker; it uses
`spawn_run` to create a Pi node-worker session;
that session uses `spawn_run` again for one Pi
edge-worker session at a time (or one approved
parallel edge set where the FSM law allows it).
Every spawn records `parent_run_id`, depth, graph,
node, and edge, so the live process tree and the
bp3 Run chain are the same shape.

```text
root Pi session (root worker; the session facing the human)
|
+-- Pi node worker A
|     +-- Pi edge worker A1 -> terminal verdict -> dies
|     +-- Pi edge worker A2 -> blocked cause -> dies
|     node worker records block -> exits
|
+-- Pi node worker B
      +-- Pi edge worker B1 -> terminal verdict -> dies
      node worker lands -> exits

root receives terminal node outcomes only; no descendant waits for input
```

Tree-death law:

1. An edge worker never waits for a human. It
   succeeds, returns a typed failure, or dies.
2. A node worker does not exit for `blocked` until
   every edge Run it spawned is terminal in bp3
   (`finished`, refused, or derived `orphaned`
   after supervisor/watch disposition).
3. Once that is true, the node worker writes the
   blocked state and exits. The root receives one
   terminal bubble: graph, node, state, reason,
   last edge, claim/run chain, desk, and inbox key.
4. The bubble carries facts, not live objects: no
   pid, process handle, session memory, or child
   continuation is needed to revive the node.
5. If a node worker dies before reaping a child,
   the root follows `parent_run_id` links, asks
   the supervisor/watch to disposition each orphan,
   and only then treats the tree as dead.
6. Revival is a fresh spawn. After the human
   answers and the conductor records `resume`, the
   root mints a new node link and spawns a new Pi
   node worker. It re-reads bp3 and claims its own
   context; the old tree is never restarted.
7. If the root session itself dies, the next main
   session revives from bp3 rollup + inbox. The
   human does not need the old root process either.

Muse follows the same terminal-bubble contract
with a workflow run as the node worker: all agents
return, the workflow exits on `blocked`, and a
fresh workflow is launched after `resume`.

## Acceptance

| Case | Expected |
|---|---|
| edge completes | bp3 records the edge verdict; the same node worker re-reads state and continues |
| Pi tree bubbles to root | a Pi edge worker's human-blocking failure causes its node worker to record `blocked` and exit; the root Pi session receives exactly one terminal bubble with graph, node, reason, last edge, run chain, desk, and inbox key |
| whole Pi tree dies | after the blocked bubble, no Pi node-worker or edge-worker process from that node remains live; process evidence is checked, not inferred from state alone |
| Pi revival is a fresh tree | after human answer + `resume`, root spawns a new node worker with a new claim/run chain; no old pid or session is resumed |
| unreaped Pi grandchild | if the node worker dies first, root follows `parent_run_id`, supervisor/watch dispositions the descendant, and only then reports the tree dead |
| root Pi session dies | a new main session reads rollup + inbox, finds the blocked node and reason, and can record the answer and spawn a fresh node worker |
| edge returns typed failure | failure is returned promptly with code, facts, guidance, and reason; no hidden retry loop changes state |
| `needs_fix` below cycle cap | no human page; node worker dispatches the fix edge carrying the reviewer's named fix verbatim |
| cycle cap exceeded | node transitions to `blocked`; node worker exits; conductor emits exactly one live page and one inbox entry |
| human decision required | node transitions to `blocked` with a specific reason; dirty work is committed only when the human needs that diff to decide |
| human answers | conductor records the answer with `resume`; a fresh node worker is launched and derives its next move only from bp3 reads |
| stale worker returns after block | its old link is spent and cannot move the node; bp3 refuses the stale edge attempt with the current state in the verdict |
| edge worker dies silently | Run is derived `orphaned`; node is not blocked; node worker mints one fresh link and dispatches one replacement |
| sibling nodes are ready | they continue while one node is blocked; only that node's dependents lose readiness |
| conductor restarts | blocked nodes and reasons are recovered from bp3/inbox without relying on any worker process or prior session memory |

## Cycle 2 fix (owner A, 2026-11-17)

Cycle-1 grade on `4d00100`: every Muse row
passed; the five Pi rows (Pi tree bubbles to
root, whole Pi tree dies, Pi revival is a fresh
tree, unreaped Pi grandchild, root Pi session
dies) were gated-`missing` because the handoff
deferred Pi process proof to an unnamed "Pi
drive". Owner chose A: do the Pi proof here.
Named fix, verbatim for cycle 2: supply the
real Pi root -> node-worker -> edge-worker
process-tree proof demanded below — terminal
bubble reaching the root Pi session exactly
once, process-table evidence that the whole
tree is dead after the bubble, `parent_run_id`
disposition of an unreaped grandchild, and a
fresh-tree revival after `resume` (new claim/
run chain, no pid/session reuse). The Pi rows
stay gated by this exp; do not re-defer them.

## Acceptance test (goal block)

- **Objective:** a blocked node costs no live
  worker, loses no decision context, and resumes
  in a fresh worker from bp3 alone.
- **Prove by:** fixture graph with independent
  siblings and a dependent; drive cases for typed
  failure, `needs_fix`, cycle-cap escalation,
  silent worker death, conductor restart, and
  human resume. Pi proof uses a real root ->
  node-worker -> edge-worker process tree and
  checks the process table after the blocked
  bubble, then revives with a fresh tree.
- **Done when:** blocked exits are observed, the
  human is paged once, siblings continue,
  dependents wait, the whole Pi tree is dead, and
  the resumed node is driven by a fresh worker to
  its next legal state.

## Tests

Known cases: the acceptance table above, tested
one case at a time against public bp3 verdicts,
ledger/state reads, worker exit status, and inbox
contents.

Property-based: for any interleaving of sibling
outcomes, a blocked node never makes an unrelated
node unready; for any worker death point, at most
one unspent replacement link is minted for the
same edge attempt; no blocked node has a live
node-worker process owned by the drive after the
blocked verdict is recorded.

Process tests must distinguish a genuinely exited
worker from a merely silent one. A test that only
checks the final node state is insufficient.

## Context

The old shape could strand attention in two ways:
a long-lived worker waiting for a human, or a
conductor trying to remember why a node stopped.
Both burn context and make recovery depend on a
session surviving. Fail-fast moves the stopping
fact into bp3 at the moment it happens. The human
gate becomes durable data, and resumption becomes
an ordinary fresh dispatch.

This node does not redefine the FSM, inbox, link,
or scheduler. It makes their failure contract
testable in the node worker that mvp.3 delivers.
