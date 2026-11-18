# bp3-control sketch: exploratory Graphs, coordinated nodes

Status: **historical sketch, superseded by the [MVP](bp3-control-mvp.md).**

Retained as design history. The MVP is the current scope and records which
implementation decisions remain proposed. This sketch is not a second live
specification; its open questions and delivery plan are historical.

## TL;DR

bp3-control is the state-aware harness/skills the user talks to. It includes
an evolving Board, Worker coordination, review, and controlled integration.
Start with one CLI and separate internal modules, not separate Controller,
Worker-reporting, and launcher binaries.

The Graph is clay; each launched node is a recorded snapshot of what we are
trying next. The planning model is **Graph -> outcome-defined nodes**, not
Graph -> Milestone -> Task -> execution attempt. Worker runs are execution
records inside an node, not another planning level.

## ELI5

Tell the Controller what you want. It helps choose useful nodes, starts
those that can run together, and brings back things you can inspect or run.
Keep what works, learn from what does not, and add more nodes as needed.
When you accept the demonstrated result, complete the Graph. If a prototype
is worth making robust, write a new hardening Graph using the completed one.

## Context

### Problem and desired working style

The user primarily delegates at Graph level. Some requests begin detailed
because the user knows the domain; others start with a reference image or a
rough idea. Exploratory work should support tinkering, not require an entire
plan before the first useful node.

An node is large enough to produce an outcome worth reviewing. The Controller
figures out prerequisites, fans out independent work, retains coordination
state, and evaluates Worker results. A Graph may gain follow-up nodes as new
information appears. Its exact shape need not be fixed upfront.

Specification effort should consider familiarity and expected longevity, but
also the consequence and reversibility of mistakes. Throwaway work is not
necessarily harmless. Exploration should ideally be sandboxed.

The model-routing hypothesis is that a well-specified node can be executed by
a cheaper model, with stronger models used for specification and review.
This is a hypothesis, not an established capability claim about any model.
Measure total specification, execution, review, and rework cost.

### Existing proposals and precedence

There is no implementation in this directory at the time of writing.
The predecessor documents are in the sibling bp3-docs project:

- Original control proposal, `bp3-docs/docs/repos/control.md`:
  Board in SQLite, disposable Controller session, operations boundary,
  independent verification, approval before publishing, and recovery.
- Original master design, `bp3-docs/docs/design.md`:
  Graph -> Milestone -> Task -> node hierarchy, pi/Zellij on a Mac mini,
  separate Worker extraction, and fail-before-start checks.

At the time of writing, this sketch superseded those proposals for this
component where they conflicted: Graph -> node, one CLI initially, explicit node
prerequisites, acceptance appropriate to exploration, `node launch`, `node land`,
and `graph complete`. The [MVP](bp3-control-mvp.md) now governs this component.
The predecessor files were not updated by this sketch.
These are provenance paths in the original local workspace, not files shipped
in this repository; bp3-docs has no configured public remote at writing time.
This design is self-contained and does not require those files to be usable.

### Constraints and non-goals

- Initial deployment follows the single-host, pi/Zellij, SQLite proposal.
- Controller sessions are disposable; important state must survive them.
- Workers execute; the Controller coordinates and independently reviews.
- No automatic publishing without recorded human authorization.
- No mandatory UI: committed artifacts, smoke tests, and repeatable demos
  can demonstrate outcomes.
- No first-class Milestone or Task entity, mandatory prototype-to-production
  lifecycle, general distributed workflow platform, or immediate launcher
  extraction.
- Hardening is a new Graph, based on a prior completed Graph.

## Design

You converse with a Controller running control skills. Skills exercise
judgment; operations enforce transitions; the Board remembers coordination;
Workers execute. The node dependency graph grows as the Graph develops.

```text
You <-> Controller session running control skills
                   |
                   | structured operations
                   v
              bp3-control CLI
                   |
         +---------+----------+
         v         v          v
       Board    Launcher     Git
      SQLite    pi/Zellij  worktrees, artifacts,
         ^         |      briefs, review packets
         |         v
         +------ Workers
          reporting operations

Graph: evolving demo-able outcome
  |
  +-- node A --+
  +-- node B --+--> node D
  +-- node C

node: versioned brief -> execution -> evidence -> review -> disposition
```

### Data models

These are logical entities, not a finalized SQL schema.

#### Graph: evolving intent

```text
Graph
  id
  intent and why
  current success picture
  constraints and budget
  state
  based_on: prior Graph/result references
  accepted demo and completion record
```

A design, benchmark, or demonstrated finding can be an output. Success need
not be a visual UI. Completion records what the user accepted and the known
limitations; it does not retroactively claim production readiness.

`based_on` supplies provenance and context, not an automatic scheduling
edge. A hardening Graph references the previous result without reopening
that Graph or inheriting every node.

#### node: bounded outcome

```text
node
  id, graph_id
  brief revision
  intended contribution, scope, non-goals, acceptance basis
  prerequisites
  budget and stopping conditions
  execution records
  selected result
  review and approval references
  state
```

An node can deliver implementation, design, comparison, or a negative finding.
An accepted finding that an approach fails is not a landed implementation.

The brief can begin lightweight. It must identify enough purpose, constraints,
and evidence expectations to authorize useful execution. Changes are explicit
revisions, not silent replacement of instructions already given to a Worker.

- Missing the agreed brief: rework within the same node.
- Wrong or incomplete brief: explicitly amend the node.
- Separate useful outcome discovered: propose a follow-up node.
- Failed approach with useful evidence: retain the findings and close the
  attempt honestly.

No first-class Task is modeled. A Worker may maintain a private checklist
without turning every implementation step into Board state.

#### Execution: a concrete run

```text
Execution
  id, node_id, brief_revision
  resolved input commits/artifacts and upstream result revisions
  harness and model
  workspace, branch, terminal/process endpoint
  session references
  output commits/artifacts
  checks and demo receipts
  lifecycle and liveness observations
```

Replacing a Worker or bringing in a stronger reviewer does not create a new
planning node. Execution records preserve which inputs produced which output.
Model selection belongs to execution/review sessions, not node identity.

Preserve distinct observations for tab existence, process liveness, and
heartbeat freshness. A stored running state alone is not evidence of health.

#### Prerequisites and lineage

Initially support:

1. A repository and exact commit prerequisite.
2. A prerequisite node's accepted result, resolved to an exact result revision
   when the downstream execution is launched.

The node graph must reject cycles, self-dependencies, and missing references.
An upstream status alone is insufficient: record the actual consumed output.

If a selected upstream result changes, affected downstream results become
stale for acceptance. Preserve old evidence. Do not automatically kill Workers
or spend money rerunning them. An execution deliberately pinned to an old
result retains that lineage; any switch to a newer result is explicit.

#### Evidence, review, and approval

```text
Result
  execution and brief revision
  output revisions/artifacts
  checks, smoke/demo commands, environment requirements
  limitations

Review
  exact reviewed result and brief revision
  deterministic check receipts
  severity-ordered findings
  verdict and reviewer session

Approval
  authorized action
  exact reviewed result / integration revision
  human decision reference
```

Changes after approval cannot inherit authorization for a different result.
Exact approval scope and integration-commit binding remain to be specified
before implementation of land.

### Functions

Command spelling below is proposed. The public naming decisions are
`node launch`, `node land`, and `graph complete`.

#### Graph definition and exploration

The Controller turns user intent into a current success picture and proposed
nodes. It asks only questions that block safe, useful progress. Exploration can
produce findings or designs without a software test that fails beforehand.

The Controller identifies common assumptions before fan-out. Complementary
nodes need shared contracts; competing nodes need a comparison basis. Being
individually runnable does not guarantee that their outputs will compose.

#### `node launch`: reserve and start

Input: node identity and execution configuration.
Output: a recorded execution and its launch endpoint, or an explicit failure.

1. Validate prerequisites, brief revision, and capacity.
2. Atomically reserve the node against competing launches.
3. Record the resolved input snapshot.
4. Prepare the workspace, composing required committed inputs.
5. Launch the Worker and record the endpoint and outcome.

This is the user-facing claim operation; callers do not need a separate
claim-then-launch sequence. SQLite transactions cannot atomically launch an
OS process. Partial progress must be recorded and reconciled after failure.
A workspace conflict blocks execution; a summary does not substitute for
having the required code or artifacts present.

The launcher is an internal adapter. It receives execution identity, brief,
workspace, and harness configuration, and returns launch/endpoint information.
It does not choose work, grade results, or authorize publishing.

#### Worker reporting and candidate submission

Workers report heartbeat and blockers through operations, not raw SQL or
pane text. An illustrative `node ready` submits output references, check
results, repeatable demo instructions, and known limitations.

The Worker submits a candidate, not an acceptance decision. Failed required
checks are recorded and do not silently become a ready result.

#### Review

The Controller evaluates artifacts and independently checks claims against
the versioned brief. Possible dispositions are acceptance, rework, an explicit
brief amendment, a question for the user, or closure with retained findings.

Automate deterministic rules where practical: formatting, lint, types,
required artifacts, test execution, revision matching, and required process
steps. Use model review for architecture, design/style judgments not encoded
in tools, missing cases, and unnecessary complexity. Resolve subjective
intent with the user rather than letting a stronger model invent it.

Reviewing exploratory findings does not authorize implementing them.
Accepting code does not inherently authorize release or deployment.

#### `node land`

Integrate a verified, approved code result into the designated Graph branch.
Serialize integration. Refuse missing, stale, or revision-mismatched approval.
Check the actual integrated result: individually passing branches can fail
when combined. Publishing requires recorded human authorization.

For non-code outputs, record acceptance of the selected artifact or findings;
do not manufacture a merge to call exploration landed. The exact non-code
acceptance command remains open.

#### `graph complete`

Record the user's acceptance of the demonstrated outcome and known
limitations. Remaining nodes need explicit dispositions; not every attempted
node needs to succeed. Completion must not leave work silently running.

A subsequent hardening Graph gets its own intent, requirements, nodes, checks,
and completion evidence, referencing the completed exploratory result.

#### Context recovery and waiting

A replacement Controller loads current Graphs, node graph, execution snapshots,
blockers, open decisions, reviews, and artifact references through operations.
Full conversation history is fetched only as needed.

The Controller waits for Board changes through the proposed long-poll/event
surface rather than reading terminal text or busy-polling panes. Notifications
mean “read current state”; they are not the sole surviving copy of a fact.
Event cursor and replay semantics must cover Controller downtime.

### Storage

- SQLite is the coordination source of truth: identities, transitions,
  dependencies, claims, execution lineage, and evidence/approval references.
- Git stores code, versioned briefs/design artifacts, review packets, and
  repeatable demo scripts. Board references identify exact revisions.
- Session archives retain conversations, linked from execution/review records.
- Rendered reports and Controller working context are derived and disposable.
- All callers use operations. “One writer” means one controlled write
  implementation, not that Workers cannot report updates.

Use a consistent SQLite backup mechanism or a stopped/checkpointed database,
not an unqualified copy of a live file. Recovery must restore referenced git
objects/artifacts as well as Board state. Schema migrations are versioned
through the operations layer; backup/restore and migrations need tests.

### Interfaces and failure modes

| Failure | Detection and containment |
|---|---|
| Duplicate launch | Transactional reservation rejects the second claimant. |
| Interrupted launch | Recorded preparation/launch stages allow reconciliation; never blindly create a second active Worker. |
| Missing or cyclic prerequisites | Reject graph mutation before dispatch. |
| Upstream input changes | Preserve lineage and mark affected results stale for acceptance. |
| Conflicting inputs | Workspace preparation blocks before Worker execution. |
| Worker dies or goes silent | Report separate process/tab/heartbeat facts; preserve work and offer explicit recovery. |
| Controller restarts | Rebuild from Board/artifact references and replay/discover pending work. |
| Result changes after review | Old review/approval cannot authorize a new revision. |
| Prototype touches valuable systems | Sandbox and explicit external-action authorization; longevity is not a safety boundary. |
| Parallel outputs fail together | Check combined integration before treating the outcome as accepted. |

One CLI is not an authorization boundary. Splitting binaries would not isolate
Workers with the same unrestricted filesystem/OS permissions either. State
transition enforcement and actual OS/credential isolation are distinct.
A concrete sandbox and approval trust model are required before claiming
untrusted Workers cannot bypass the protocol.

## Alternatives

- **Keep Milestone and Task:** rejected for now because they expose planning
  bureaucracy below the outcome the user delegates. Revisit only when real
  coordination needs cannot be represented by nodes plus execution records.
- **Freeze the whole Graph upfront:** rejected because discovery changes the
  work. Version launch inputs instead of pretending intent never evolves.
- **Separate Worker/launcher CLI immediately:** deferred. Extract when remote
  deployment, independent consumers, packaging, or a real privilege boundary
  supplies a concrete reason.
- **Every node check must fail before launch:** rejected as a universal rule.
  Use fail-before/pass-after checks where they express an implementation
  outcome; research requires inspectable evidence and explicit questions.
- **Adopt Invoker wholesale:** not proposed. Borrow dependency validation,
  immutable input lineage, and invalidation principles without assuming its
  whole workflow platform is needed.
- **Automatically rerun stale descendants:** rejected initially to avoid
  hidden spend and overwriting useful nodes.

### Invoker evidence

Targeted source inspection at commit
[`79b62e131692614b9b5247520bf8c8e7eb03f248`](https://github.com/Neko-Catpital-Labs/Invoker/tree/79b62e131692614b9b5247520bf8c8e7eb03f248):

- [`validateDAG`, `getReadyTasks`, and `getTransitiveDependents`](https://github.com/Neko-Catpital-Labs/Invoker/blob/79b62e131692614b9b5247520bf8c8e7eb03f248/packages/workflow-graph/src/dag.ts)
  validate references/cycles, select dependency-ready work, and find descendants.
- [`MUTATION_POLICIES` and `applyInvalidation`](https://github.com/Neko-Catpital-Labs/Invoker/blob/79b62e131692614b9b5247520bf8c8e7eb03f248/packages/workflow-core/src/invalidation-policy.ts)
  distinguish scheduling changes from execution-input changes and orchestrate
  invalidation/cascades.
- [Cycle regression tests](https://github.com/Neko-Catpital-Labs/Invoker/blob/79b62e131692614b9b5247520bf8c8e7eb03f248/packages/workflow-core/src/__tests__/repro-cyclic-deps-accepted.test.ts)
  document cyclic work remaining pending while a merge gate appeared ready,
  and assert rejection of cyclic plans.

These are source-backed observations, not runtime verification, a complete
security audit, or a code-adoption/license review.

## Tests

Acceptance scenarios for an implementation that does not yet exist. No
executable suite has been created or run, so these are not reported test
failures or passing claims.

| Named check | Acceptance observation |
|---|---|
| Dependency fan-out/fan-in | A and B run in parallel; C cannot launch until its accepted inputs exist and are resolved. |
| Graph validation | Missing references, self-dependencies, and cycles are rejected without partial mutation. |
| One active launch | Two launch requests for the same node produce one active execution and one explicit rejection. |
| Partial-launch recovery | Interrupt preparation/launch; recovery reconciles existing resources without duplicate Workers. |
| Disposable Controller | Restart while Workers progress; replacement discovers results and briefs accurately. |
| Input lineage | Execution records identify exact brief and input revisions. |
| Stale descendants | Change a selected upstream result; affected acceptance is blocked without automatic reruns. |
| Evidence-backed review | Independently run the committed smoke/demo command and record the exact reviewed output. |
| Approval binding | Change output after approval; land refuses the old authorization. |
| Combined-result check | Incompatible individually passing results cannot silently become accepted integration. |
| Graph completion | Accepted demo and limitations are recorded; remaining work has explicit dispositions. |
| Hardening provenance | New Graph references the completed exploratory result without modifying the old completion. |
| Restore | Restore consistent Board backup plus referenced artifacts; context and demo remain reproducible. |

## Proposed milestones

These are Markdown delivery proposals, not Board entities or created work.

1. **Recoverable dependency-backed launch** — check: on a scratch repo, A/B
   launch concurrently, C waits for accepted inputs, duplicate launch is
   rejected, interrupted launch is reconciled, and a replacement Controller
   recovers the same picture — depends on: none. This exposes the core
   coordination risk before optimizing model routing or adding many harnesses.
2. **Evidence-backed acceptance and integration** — check: submit a committed
   smoke demo, independently review it, land only the authorized revision,
   and reject both stale approval and incompatible combined output — depends
   on: 1 and resolution of approval/sandbox questions below.
3. **Safe evolution and Graph completion** — check: amend inputs and expose
   stale descendants without automatic reruns; add a follow-up; complete the
   exploratory Graph; create a separate hardening Graph from its recorded
   result; restore the resulting state and artifacts — depends on: 2.

## Open questions

1. **Sandbox and approval authority** — owner: user + implementer. Which OS,
   filesystem, credential, and external-action boundaries stop Workers from
   bypassing operations or forging approval? This changes deployment and
   potentially whether a privileged service is necessary.
2. **Exact integration authorization** — owner: user + implementer. Define
   human approval scope, Graph-branch versus external publication, and how
   approval binds to the checked integration commit. Preserve the existing
   no-unsigned-publishing rule until this is resolved.
3. **Non-code acceptance command and lifecycle** — owner: user + designer.
   Specify explicit accepted/findings/discarded states without abusing land
   or treating useful negative findings as implementation success.
4. **Events and crash recovery protocol** — owner: implementer. Specify
   durable cursor/replay semantics, launch reconciliation, and restart-safe
   integration recovery before relying on long-poll notifications.
5. **Minimal scheduling and mutation semantics** — owner: implementer with
   user input. Define capacity/budget controls and whether prerequisite
   edits apply only to future executions or explicitly supersede active ones.
6. **Model-routing economics** — owner: user + evaluator. Which representative
   nodes establish total cost and quality for cheaper execution plus stronger
   review, including rework?

## Red chair record

### User input

Strongest attack: flexible, clay-like Graphs could leave Workers executing
instructions whose meaning changes underneath them. Change: separate evolving
Graph intent from versioned node briefs and immutable execution input snapshots.
Hardening is explicitly a new Graph. Unanswered: precise mutation behavior for
active executions remains open question 5.

### Problem space

Strongest attack: the original hierarchy and fail-before-start rule impose
implementation bureaucracy on discovery. Change: collapse planning to Graph
and node; make acceptance evidence appropriate to the outcome. Negative
findings and designs can be useful results. “Throwaway” does not waive safety.
Unanswered: sandbox enforcement remains open question 1.

### Solution

Strongest attack: readiness alone does not prove correct inputs, integration,
or authorization. Change: resolve exact lineage, check composed inputs and
outputs, invalidate stale acceptance, and bind approval to revisions. A shared
CLI is not described as a security boundary. Unanswered: approval, non-code
acceptance, and crash protocols remain open questions 2–4.

### Milestones

Strongest attack: a successful ten-Worker demo would hide the difficult
coordination failures. Change: first deliver dependency gating, duplicate
rejection, partial-launch reconciliation, and Controller restart recovery.
Evidence-backed integration precedes broader lifecycle polish. No code, Board
work, or executable acceptance tests are created by this document.

## Handoff

This sketch is frozen as historical background. Continue design and link the
governing implementation packet from the [MVP](bp3-control-mvp.md), not here.
No implementation packet existed when this sketch was superseded.
