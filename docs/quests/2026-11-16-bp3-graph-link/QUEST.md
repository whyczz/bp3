---
status: proposed
home_repo: bp3
date: 2026-11-16
---

# 2026-11-16-bp3-graph-link

## TL;DR

Three owner-settled changes to the bp3 harness
ecosystem, in dependency order. (1) Every edge
execution claims a magic link first: conductor
mints a one-time link, the child claims it as its
first action, and the claim atomically binds
session-id <> run-id in the common-dir hard store;
bp3 then resolves context from the store and env
vars are demoted to hints. (2) The graph schedules:
BFS ready-sets (cohorts) with per-node timing
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
| graph | quest | the whole work graph; a goal pursued as a graph |
| goal (G) | quest, as owner-facing word | G stands for goal and graph; skills are the `bp3g` family (`/bp3g`) because bare "goal" collides across harnesses |
| node | exp / experiment | one work unit in the graph; conductor dispatches nodes |
| state | FSM state | where a node rests (todo, submitted, approved, landed, blocked, deleted) |
| edge | transition / engine-fsm-edge | one transition of a node's FSM, executed by exactly one subagent Run |
| dep | depends_on / railway order | a link between nodes; not an edge |
| cohort | fan-out group (retired) | one BFS layer of ready nodes |
| link | (new) | one-time claim token binding a session to one edge execution |
| Run | Run | one subagent execution of one edge (unchanged) |
| tape | tape | the harness session recording (unchanged) |

States rest in the conductor's read. Edges are
subagents. A child holds nothing across edges;
context is claimed, never remembered.

## Success picture

A conductor dispatches a node with a one-line
brief: "claim this link, do this edge." The child
claims, works, calls its own edge, dies. Ready
nodes in a cohort build and grade in parallel
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
| `bp3 harness link` mint/claim, CAS claim store, by-session index, context resolution | lifecycle derivation semantics (unchanged) |
| BFS ready-set/cohorts, per-node timing derived from ledger + derivations, local thresholds | anything committed for metrics; timing judgments stay in `<git-common-dir>/bp3/` |
| setup timing measured always; optimize only when setup > 3 min (`W_SETUP_SLOW`) | desk pools (killed 2026-11-16; ad hoc desks, measured) |
| generated ASCII/mermaid diagram from live rollup | writing into harness session logs (tapes stay harness-written) |
| rename last: `bp3 g`, `bp3g` skills, graph terms on live surfaces | rewriting landed quests' ledger history text |
| session-id discovery: muse, pi; graceful floor (pid+cwd+window) | adversarial threat model (links are for confused children, not attackers) |

## Timing gates (in-system, local)

- Per node: `wall` (first submit → land), `wait`
  (create → first submit), `dwell` per state,
  cycles. Derived from ledger timestamps, shown
  on read, thresholds local, never committed.
- Per Run setup: desk create → first bp3 answer;
  `W_SETUP_SLOW` when > 3 minutes.
- Scorecards report wall minutes AND tokens per
  node. Visibility, not caps.

## Human touchpoints

- Blocked gates only, per conductor rails.
- quest_fin promotion — owner, after demo.

## Exps

Exp display names are `<milestone>.<number> - <slug>`.
Folders and bp3 exp IDs use the dotless spelling
`exp-<milestone>-<number>-<slug>`.

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
BFS cohorts from node deps; rollup emits ready
nodes and per-node wall/wait/dwell; setup timing
per Run with the 3-minute `W_SETUP_SLOW` gate.
Parallel build/grade in per-node desks, serial
land queue semantics stated and readied.

### mvp.4 - diagram-emit — [record](experiments/exp-mvp-4-diagram-emit/EXPERIMENT.md)
Generated ASCII + mermaid from a live rollup:
nodes with state/cycle, deps as cohorts, blocked
nodes naming what they starve.

### Milestone: dogfood — use it ourselves

### dogfood.1 - link-drive — [record](experiments/exp-dogfood-1-link-drive/EXPERIMENT.md)
A/B proof on the flappy node: old brief vs link
brief on both harnesses, seeded setup attacks
refusing at claim. Metrics are the acceptance.

### dogfood.2 - parallel-drive — [record](experiments/exp-dogfood-2-parallel-drive/EXPERIMENT.md)
Two independent flappy-variant nodes, one cohort,
parallel desks, parallel build+grade, serial
land. Scorecard: wall and tokens per node.

### Milestone: rename — migrate everything, last

### rename.1 - bp3g-rename — [record](experiments/exp-rename-1-bp3g-rename/EXPERIMENT.md)
Full rename on live surfaces: `bp3 g` CLI door,
graph/node/state/edge/dep vocabulary, skills
become the `bp3g` family (`/bp3g` conducts,
`bp3g` variants for framing/no-human), launcher
workflows, templates. Old terms grep to zero on
live surfaces; landed ledger text is history.

### Milestone: landing

### landing.1 - landing-wrapup — [record](experiments/exp-landing-1-landing-wrapup/EXPERIMENT.md)
Scorecard (timing included), findings
disposition, landing walkthrough actually run
(red-ink-quest-landing-demo diligence), for the
owner's promotion review.

## Scorecard

Fields: claims observed (minted/claimed/spent),
context resolutions, per-node wall/wait/dwell,
setup wall per Run, cohort wall vs serial estimate,
tokens per node, drives observed per harness,
human-active minutes — or "unmeasured", never zero.
