---
date: 2026-11-16
goal: ../GRAPH.md
exp: mvp.1
status: proposed
---

# mvp.1 - link-claim: one-time link binding session to edge

## TL;DR

The conductor mints a one-time link for one edge
execution (`bp3 harness link mint`). The child's
first action claims it (`bp3 harness link claim <token>`).
The claim is a compare-and-swap in the common-dir
hard store: exactly one winner; a second claim
refuses `E_LINK_SPENT` naming the first claimant.
The claim records caller facts — pid, cwd, desk,
and the session-id when the harness offers one —
and writes the by-session index: session-id <>
run-id, the join the grader and bind-tape need.

## Demo (design trace)

```text
conductor: bp3 harness link mint --kind edge --graph G --node N --edge handoff
  -> {token: bp3link_7f3a…, run_id: 2026…-handoff-pi-…-c1}
brief (one line): "claim bp3link_7f3a…, then build X"
child: bp3 harness link claim bp3link_7f3a…
  -> claimed {run_id, session_id, pid, desk}
child again / quoting child: bp3 harness link claim bp3link_7f3a…
  -> E_LINK_SPENT {first_claim: {session_id, pid, ts}}
```

## Diagram

```text
mint ─► runs/<run_id>.json {kind, graph, node, edge?, parent_run_id,
         depth, desk, token_hash, state: minted}   (created at mint)
claim: CAS minted -> claimed on that run config   (one winner)
         ├─► store/by-session/<session-id> -> run_id
         └─► desk context file {run_id, graph, node, edge}
```

## Pseudocode

```python
def mint(kind, graph, node, edge, desk):  # kind: node|edge
    run_id = mint_run_id(edge, harness, model, cycle)
    write(f"runs/{run_id}.json", {kind, graph, node, edge, parent, depth, desk, token_hash, state: minted})
    return token

def claim(token):
    facts = observe_caller()  # pid chain, cwd, session-id if offered
    cas_state(run_id, minted->claimed, facts) or refuse E_LINK_SPENT
    write_context(desk_of(token), facts.run_id)
    if facts.session_id: index_session(facts.session_id, facts.run_id)
```

| Field | Value |
|---|---|
| Intent | one claim per edge execution; session-id becomes a primary key |
| Lane | standard |
| Output | `bp3 harness link` (mint/claim), claim store + by-session index under `<git-common-dir>/bp3/` |
| Depends on | none |

## Acceptance

| Case | Expected |
|---|---|
| mint + claim | claim returns the minted run-id with caller facts; InitRecord-equivalent row exists in the store before child work |
| one winner | second claim of the same token (same or different session) refuses `E_LINK_SPENT` and names the first claimant's session/pid/ts |
| by-session join | given only a session-id from a tape, one lookup returns run-id, graph, node, edge |
| session-id offered vs not | muse claim records a session-id when the harness exposes one; pi claim records the dispatcher's session file identity; neither harness: claim still succeeds on pid+cwd facts (graceful floor) |
| Pi engine MVP v2 nesting | a spawned Pi node-worker session is explicitly loaded with `bp3-pi`; its `spawn_run` edge child claims a distinct link. Every claim records `parent_run_id`, depth, graph, node, and edge, so root -> node worker -> edge worker can be reconstructed from bp3 alone |
| missing Pi extension in child | if a Pi child cannot prove the `bp3-pi` tools are loaded before work, it refuses before doing edge work with a typed setup failure; it never silently becomes an unsupervised worker |
| run config replaces InitRecord | mint writes `creator:{}` (parent run_id, depth, harness, model, minted_at, token_hash); claim writes `claim:{}` (session_id, pid, cwd); `bind-tape` writes `tape_path` into the run config; the supervisor fold derives lifecycle (`init/active/finished/orphaned`) from this one file + tape + pid, matching the old fold on harness fixtures; `bp3 harness record-init` refuses as retired |
| claim CAS is real (red-chair) | the CAS is an O_EXCL claim marker, not a file edit: two parallel claims of one token produce exactly one winner and one `E_LINK_SPENT`; run config writes are single-write temp+fsync+rename, and a torn run config is never read as valid |
| depth cap (red-chair) | mint beyond the depth cap (default 3: root/node/edge, machine-config overridable) refuses `E_DEPTH`; the Pi tree cannot fan out past it |
| stale mint cleanup | `bp3 harness link cleanup --graph <graph>` removes every still-`minted` run config of that graph and reports them; other graphs' rows and all claimed run configs/derivations are byte-identical before/after; no TTL anywhere |
| quoting safety | a token appearing in briefs/matrices confers nothing until claimed; spent tokens refuse forever |
| env-set run-id (owner ruling from mvp.1 of the supervisor graph) | run-id arrives via the claim, not typed env prefixes; bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; hooks witness does not gate |

## Acceptance test (goal block)

- **Objective:** an edge execution is claimable
  exactly once, and its session is joinable to its
  run-id forever after.
- **Prove by:** mint/claim drive on muse and pi
  shapes (fake + real), double-claim refusal,
  by-session lookup from a tape's session-id.
- **Done when:** double claim refuses
  `E_LINK_SPENT` naming the winner, and the join
  resolves, observed.

## Tests

Store-level: CAS race (parallel claims, one
winner), spent permanence, torn-write tolerance
(followup.1 discipline: single write, rename).
Harness-level: fake-muse and fake-pi claim
fixtures; session-id present/absent cases.
Regression: claims write nothing into harness
session logs (tape byte-identical apart from the
child's own tool call).

## Context

Replaces the brief-carried setup ritual and the
post-hoc tape archaeology of followup.4 in the
supervisor graph: binding used to be resolved
after the child died, from quoting-prone text.
Now it is claimed before work starts, by the
only session that will do the work. Threat model
is confused children, not adversaries: tokens in
briefs are capabilities, single-use and loud.
