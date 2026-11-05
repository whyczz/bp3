# bp3-control MVP: understandable coordination, useful delivery

Status: **MVP scope agreed; implementation design being scoped.**
No implementation, Board records, or executable acceptance suite exists yet.

This document is the current MVP scope. It supersedes the
[original architecture sketch](bp3-control.md) where they differ. The sketch
is retained as background, not as a second specification. Product decisions
below are agreed; implementation proposals and open questions are labeled.

## TL;DR

Help the user **learn more and deliver more with less time and higher-signal
human input/output**. The user directs intent; a lightweight Controller frames
Quests and exps, delegates all execution to Workers, synthesizes evidence, and
owns landing mechanics. The human authorizes land and push.

Build the smallest reliable, single-host coordination loop, then use it to
implement **esc3**. Optimize for useful outcomes and human attention, not Worker
count, parallelism, or cheap tokens in isolation.

## ELI5

A Quest says what we want and why. An exp says what useful thing to try next
and how we will judge it. Workers do the work. The Board remembers what they
were told, what happened, and what remains unresolved. You get a short briefing
and a recommendation when your judgment is needed, not a scheduling job.

## Context

The repository at `2c8a08654d0d5fde83052c7fef3f1a04283a409b` contained only
`readme.md` and the architecture sketch. There is no runtime to claim reliable.
This MVP records the subsequent review and user clarification.

Three findings shape the next design:

- **Understandability is the data-model requirement.** The user must be able
  to reason about a clear Quest and clean exps. Fewer SQL tables or edge types
  is not the goal by itself. Do not introduce a general graph vocabulary where
  a named relationship would be clearer.
- **Reliability is still a design obligation.** The sketch names launch,
  review, land, lineage, and recovery, but does not fully specify their
  transaction boundaries, authority, retries, or reconciliation.
- **A rewrite is not proof of value.** `esc2/docs/m1.md` reports successful
  logging but unused comparisons/metrics. esc3 must deliver useful queryable
  recaps, while separately testing bp3's coordination.

Local provenance, not vendored dependencies: the sibling `bp3-docs` at
`99c111479a7bc79eabbcc37e8638fb9dee8bb8df` still describes Task/Milestone
identities in `docs/repos/worker.md` and exp-only attribution in
`docs/repos/archive.md`. Its `docs/repos/control.md` proposes OCaml/SQLite.
Those contracts must not silently override this MVP. The esc2 reference is
`c8baf953d658fb3ccac3c92e331842a041480c35`; see its `README.md`, `docs/m1.md`,
`src/core/schema.sql`, and `test/cli/`. No esc2 runtime tests were run for this
document.

## Agreed MVP contract

1. **Goal:** more learning and accepted delivery per unit of human attention.
2. **Planning:** evolving Quests and bounded, outcome-defined exps; executions
   are records inside an exp, not another planning layer.
3. **Delegation:** all execution work, including small implementation changes,
   goes through an exp and a Worker. The Controller coordinates and synthesizes.
4. **Authority:** the human controls intent and explicitly authorizes land/push;
   Controller ownership of the process is not permission to approve it.
5. **Blockers:** every blocked Worker notifies the user through an IIUC-style
   recap, red-chaired next steps, and a recommendation.
6. **Waiting:** deterministic watchers, signals, timers, and long-polling are
   allowed. No model-driven polling or cron loops; routine notifications do not
   trigger model turns. Actionable events may trigger coalesced paid turns.
7. **Environment:** worktrees first, on one host, with SQLite and pi/Zellij.
   Colima/Docker or stronger isolation is a follow-up, not a claimed property.
8. **Dogfood:** bp3 drives esc3 implementation: esc2 MVP capabilities, clearer
   data, and queryable day/week recaps. Projections mean recaps, not forecasts.
9. **Success:** a useful real-day result, independent checks, Controller restart
   recovery, a blocker briefing, and no unauthorized land or push.

### The human-facing model

```text
Quest — What outcome are we pursuing, and why?
  └─ exp — What bounded contribution or question are we tackling next?
       └─ executions — Which Workers tried it, with which inputs and results?
```

Only Quest and exp are planning concepts. Results, reviews, questions,
permissions, and integration records explain the work; they are not new queues
for the user to manage. A Worker can keep a private implementation checklist.

An exp may produce code, a design, a comparison, or an accepted negative finding.
Rework against the same brief is another execution; a changed brief is an
explicit revision; a separate useful outcome calls for a new exp. Review does
not automatically create another planning exp.

An illustrative esc3 Quest might contain a model comparison, an implementation
of the selected model, and queryable recaps. Dependencies name the accepted
results needed next, not a collection of vague "related to" edges. These are
examples, not created Board records or a frozen esc3 plan.

### The human interface

The normal briefing answers: **what was achieved, what was learned, which
decision needs you (with a recommendation), and what happens next**. Suppress
progress chatter without hiding failures or consequential uncertainty.

A blocker briefing contains:

- **IIUC:** intended outcome, what the Worker tried, and what now blocks it.
- **Red chair:** challenge the proposed next steps; identify the strongest
  objection, relevant evidence, and remaining uncertainty.
- **Recommendation:** the preferred next action and the decision needed from
  the user, if any; say what can continue meanwhile.

The Controller may synthesize multiple notifications into one briefing, but no
blocker disappears through coalescing. A transport acknowledgement is not proof
that a question was seen, answered, or handled.

## Implementation design scope — proposed

This section proposes boundaries and contracts, not a finalized SQL schema,
command list, or authorization mechanism. Resolve these before implementing
the corresponding behavior; do not reopen settled product decisions.

### Architecture

Keep one CLI/codebase with separate internal modules for operations, storage,
launch, runtime supervision, and integration. Start with pi; do not implement
four production harness adapters before proving one.

```text
Human <-> Controller (pi; intent clarification and judgment)
                |                                  ^
                | operations                       | bounded actionable wake
                v                                  |
            bp3 CLI <-> SQLite Board <-> deterministic runtime
                ^                                  |
                | reports / questions              | launch / reconcile / stop
                +------------- Workers ------------+
                         pi / Zellij / worktrees
                         implementation and independent review
```

**Recommended starting point, not a settled language decision:** preserve the
predecessor's OCaml/SQLite core and use a thin TypeScript pi adapter. Compare
that with a TypeScript core only if it materially simplifies the runtime and
adapter contract. One CLI does not require one OS process.

**Recommended runtime ownership:** a deterministic local supervisor owns
reconciliation, event following, liveness, and enforced limits even when the
Controller model is idle or its session exits. A thin pi bridge displays
notifications and requests actionable turns. The supervisor is not another
LLM Controller and cannot invent work or approval. Its precise lifetime,
singleton claim, and reconnect protocol are the second design slice below.

### Data models

Logical records and the fields that matter; exact tables and state enums remain
to be designed. Avoid a universal node/edge store for this control plane.

| Record | Responsibility and essential data |
|---|---|
| Quest | Intent, why, success picture, constraints, state, human acceptance, optional prior-result provenance. |
| exp | Quest ID, versioned brief, bounded contribution, expected result kind, acceptance basis, prerequisites, limits, selected result, disposition. |
| Execution | Exp ID, role, ownership generation, immutable brief/input revisions, harness/model/version, workspace, endpoint/session, desired state and observed liveness. |
| Result | Execution ID, exact output commits/artifacts, result kind, evidence claims, limitations; useful findings need no fabricated merge. |
| Review | Exact result/brief, independent reviewer or verifier execution, check receipts, findings, verdict. Worker claims remain separate from verifier receipts. |
| Question/reply | Execution and question identity, blocker, answer/decision reference, delivery and handling state. |
| Approval/integration | Human decision reference, exact authorized action/target/revision, expected target commit, checked integration commit, durable operation journal. |

Idempotency receipts, revisions, ordered events, and consumer cursors are
protocol machinery, not planning entities. Preserve `quest_id`, `exp_id`,
`execution_id`, `result_id`, `review_id`, and session role across adapters and
future archive integration. An exp ID alone cannot identify a particular run
or review.

Load-bearing invariants:

- Launch resolves exact inputs. Later Quest/brief edits do not rewrite what a
  Worker was given. Replacement and review runs retain separate attribution.
- Prerequisites distinguish a code artifact from a finding; an accepted
  negative finding cannot accidentally satisfy a required-code input.
- Cycles, self-dependencies, missing references, and incompatible input
  composition are rejected before launch.
- A changed selected result, an intentional old-result pin, and withdrawal of
  an invalid result have distinct consequences. Preserve evidence, block
  inappropriate acceptance, and never silently spend money rerunning work.
- Desired state, process liveness, terminal existence, and report freshness are
  distinct observations. A stored `running` label proves none of the others.
- Submission is not review; review is not human authorization; authorization
  for one revision/action is not permission for another.

### Functions and Worker protocol

Names describe responsibilities, not implemented command spellings.

| Operation | Responsibility and failure behavior |
|---|---|
| Define/amend Quest or exp | Record intent and explicit revisions; reject invalid dependencies; identify consequences for existing executions/results. |
| Launch | Validate scope, prerequisites and capacity; reserve execution ownership; freeze inputs; prepare worktree; start and handshake from the actual Worker environment. Reconcile partial launch instead of blindly retrying it. |
| Report / ask / reply | Persist progress, blockers, candidates, and answers with stable identities. Workers cannot accept their own result or authorize land through reporting operations. |
| Review | Dispatch independent inspection/check execution against exact outputs; retain receipts and return a bounded review packet to the Controller. |
| Prepare / authorize / land | Compose and check the actual integration, request human permission, and conditionally update only the authorized target. Journal partial progress for recovery. |
| Context / query / recap | Return current coordination and evidence references, including unresolved obligations; full transcripts are fetched only when needed. |
| Cancel / replace / complete | Record desired state, fence obsolete ownership, reconcile the process outcome, and explicitly dispose of remaining work before Quest completion. |

Proposed mutation envelope: protocol version, stable operation ID, execution
ID/ownership generation where applicable, expected entity revision for
conditional mutations, operation, and payload. The adapter supplies mechanical
identity and preserves it across retries. Same ID and same payload replays the
recorded outcome; same ID with different payload fails. Obsolete ownership
cannot create new mutations. The transition contract must define the ordering
between duplicate detection, ownership checks, and cancellation/completion races.

The Worker receives a bounded brief: objective, acceptance, scope/non-goals,
exact inputs, authority, limits, submission requirements, runtime stamps, and
current coordination/questions. Do not forward the Controller's entire history.
For v1, a Worker may submit a candidate or `needs_input` and stop; only the
Controller initially needs autonomous idle wake.

### Storage and projections

- **SQLite:** coordination source of truth, including mutation receipts and
  pending obligations. State mutation and its event share one short transaction.
- **Git/artifacts:** versioned briefs, code, review packets and other evidence,
  referenced by exact revisions. Referenced objects must survive cleanup.
- **Session files:** execution/review conversation evidence, linked by role and
  execution identity; not the source of coordination state.
- **Projections:** derived, queryable views, not a second editable source of
  truth. A recap states its window, time zone, source revisions/cursor, and
  evidence links. A generated narrative does not become an authoritative fact.

For bp3, proposed day/week and Quest recaps cover outcomes, learning, blockers,
decisions, next actions, and available cost/attention observations. For esc3,
recaps cover recorded activity, plans, contexts/goals, and metrics. These are
separate domains/stores, not a shared generic graph schema. Historical
"as known then" versus current-corrected views must be specified rather than
silently conflated.

No SQLite transaction spans a process launch, Git command, or model call.
Backups use a consistent SQLite snapshot plus referenced Git/artifact objects;
a casual copy of a live database is not a restore contract. Version migrations
and test restore in a fresh location.

### Interfaces, authority, and failure modes

**Cooperative worktrees, not hostile-code isolation.** Workers and check runners
may share filesystem access, Git metadata, credentials, and network access.
Controlled operations prevent protocol mistakes; they do not prevent an
unrestricted same-user process from bypassing them. A local service alone would
not fix that. Do not claim a sandbox or safe execution of hostile checks.

Run independent checks in a separate verifier environment with the narrowest
practical authority, not inside the Controller session merely because a Worker
supplied a command. The later isolation exp must cover both Workers and check
runners. The concrete human approval entry path remains a pre-land design gate;
a model-supplied `actor=human` field is not proof of permission.

Proposed land transaction: record expected target **B**, construct integration
commit **I**, check **I**, obtain human authorization for the exact action/target
and **I**, then conditionally update the target only if it still equals **B**.
Persist enough journal state to reconcile a crash between Git and SQLite.
Target movement requires re-preparation and renewed authorization. Pushing or
publishing needs explicit scope; permission for local land alone is insufficient.

| Failure | Required containment |
|---|---|
| Lost response / duplicate report | Replay the committed operation outcome; do not duplicate results or obligations. |
| Competing Controllers / stale Worker | Conditional revisions and ownership generations prevent conflicting reservations or stale mutations. |
| Launch or integration crash | Durable stages and reconciliation discover what happened before retrying side effects. |
| Missed notification / watcher death | Board obligations survive; reconnect and replay discover them. Distinguish recorded, transport accepted, observed, and handled. |
| Busy or permission-blocked harness | Preserve pending delivery; acceptance by transport is not evidence of a model turn or user acknowledgement. |
| Capacity or budget exhaustion | Defined stop/escalation behavior, independent of model polling. Unknown cost is reported unknown, not zero. |
| Output changes after check/approval | Reject mismatched or stale review/authorization; check the actual combined integration. |

## Scope boundaries and alternatives

In: one host, one CLI, SQLite, pi/Zellij, worktrees, bounded Worker briefs,
durable reports/questions, deterministic waiting, independent review, authorized
land, recovery, and queryable evidence-backed recaps. Retain small-scale
fan-out/fan-in without building a general scheduler.

Not required for the MVP:

- A Task/Milestone planning hierarchy, universal graph engine, or workflow DSL.
- Four production harness integrations, remote Workers, a web UI, or immediate
  extraction into separate Controller/Worker/launcher products.
- Colima/Docker isolation, hostile-Worker security claims, or unrestricted
  external actions. Isolation remains a follow-up, not a dismissed risk.
- Automatic reruns of stale descendants, automatic land/push, forecast engines,
  archive mining, or model-routing optimization before end-to-end value exists.

The boring comparison is a simple Worker runner plus a concise durable ledger.
If bp3 costs more human attention without better recovery, evidence, or outcomes,
keep the simpler loop. Evaluate targeted protocol patterns rather than importing
an entire orchestration platform. More parallelism is not itself an acceptance
test.

## esc3 dogfood Quest

Use esc2's implemented MVP as the behavioral reference, not a requirement to
copy its schema or preserve known reporting defects. Its capabilities include
plan/done capture, temporal nesting, contexts, tags, declared metrics,
corrections/history/provenance, plan copying, comparison/rollups, and text/JSON
operation surfaces. Its existing MCP surface is part of the reference inventory;
any staged parity deferral must be explicit, not silently omitted.

Add queryable daily/weekly recaps and demonstrate clearer data with concrete
records, queries, and reports. One activity may contribute to multiple goals;
goal totals may overlap, but elapsed time must not multiply with graph links.
The graph/storage representation is an early esc3 exp decision, not settled by
this document. Use a new project/database; leave the existing esc2 data intact.
The broader Python/web/auth/audio Escapement application is not the scope.

The Controller frames the Quest and exps; Workers compare models, implement,
and independently verify. Test nesting, overlaps, midnight, corrections,
missing-data versus zero, and multi-goal accounting on reproducible fixtures.
Then the user uses esc3 for one real day and judges whether the recap is useful.
Do not call a direct Controller-written rewrite "bp3 dogfood."

## Tests

These are proposed acceptance checks. They are unmet because the implementation
is absent, not reported executions of a failing test suite.

| Check | Acceptance observation |
|---|---|
| Understandable model | From a Quest view, the user can explain why each exp exists, what it needs, what it produced, and the next decision without reading transcripts or raw SQL. |
| Worker round-trip | A real pi Worker in its worktree handshakes, reads the exact brief, reports a blocker/candidate, and safely retries a lost response. Cross-execution mutations are rejected by the protocol. |
| Protocol counterexamples | Duplicate/conflicting operation IDs, stale ownership, dependency cycles, invalid result kinds, and cancellation/completion races have deterministic outcomes. |
| Tokenless waiting | Proposed 30-minute idle run has zero waiting-attributable provider requests; routine events do not start turns; actionable wakes are bounded and coalesced without losing obligations. Account for unrelated harness background traffic; do not assume exactly-once external delivery. |
| Disposable Controller | Restart during work and during a pending question; replacement reconstructs current state and obligations without duplicate launches or repeated explanation from the user. |
| Blocker briefing | A forced blocker reaches the user with IIUC, challenged next steps, and a recommendation; reply is traceable through handling. |
| Lineage and composition | Fan-out/fan-in consumes exact inputs; selection changes, pins and invalid withdrawals do not silently validate incompatible or stale outputs. |
| Review and authorized land | Independent checks bind to the actual integration; absent/mismatched permission or target movement prevents land. Crash recovery reconciles Git and Board. |
| Limits and restore | Exhaust a configured limit; interrupt the runtime; restore Board plus referenced artifacts in a fresh location without lost or silently resumed obligations. |
| Useful dogfood | bp3 drives esc3 implementation and the real-day trial; the user gets an inspectable result, short learning summary and clear acceptance decision without manual scheduling. |

Measure human active time, interventions/repeated explanations, accepted
outcomes, useful learning, elapsed time, and total model/check/rework cost.
Unavailable measurements remain explicit. A low token bill with more human
babysitting is not success.

## Proposed delivery milestones

These are design-stage experiment proposals, **not created Board records or a
new Milestone entity**. Scope each exp around an inspectable output.

| Exp | Shippable output and decisive check | Depends on |
|---|---|---|
| E0 — Protocol counterexamples | Small transition/identity contract with executable fixtures for retries, ownership, result kinds, and races; each disputed transition has an expected outcome. | None |
| E1 — Worker reaches Board | Minimal CLI/Board plus real pi worktree handshake, immutable brief, blocker/candidate report, and retry check. | E0 |
| E2 — Tokenless waiting | Deterministic runtime/pi bridge; idle, busy, restart, permission-wait and watcher-death traces meet the notification contract. | E1 |
| E3 — Crash/replacement | Interrupt launch/report boundaries; competing Controllers and resumed old Workers cannot duplicate or corrupt committed work. | E1–E2 |
| E4 — Evolving lineage | Executable fan-out/fan-in, pin, amendment, negative-finding and withdrawal cases; incompatible inputs fail before dispatch. | E1, E0 lineage rules |
| E5 — Review/integration | Independent verification, concrete human approval path, exact-commit conditional land, and Git/Board crash reconciliation on a scratch repo. | E1, E3–E4 |
| E6 — esc3 through bp3 | Real esc3 Quest and real-day trial, including a blocker, Controller restart, limits and fresh-location restore. | E2–E5 |
| E7 — Worth building? | Compare attention, learning, accepted delivery and total cost with the simpler runner/ledger baseline; retain or cut complexity from evidence. | E6; record baseline before E6 |

Prioritize E0, E1 and pi-only E2. E0 must stay small and feed the real round-trip,
not become months of abstract protocol design. Other harnesses and isolation
can be subsequent exps without blocking proof of the cooperative pi workflow.

**Bootstrap proposal:** before the Board can launch its own implementation,
record bootstrap exp briefs, stable identities, Worker sessions, results,
reviews and human land permissions in a temporary durable file ledger. Launch
those Workers manually and import the records idempotently once E1 works. This
is an exception in transport, not an exemption from Worker execution, review,
or human permission. It is not yet automated bp3 dogfood. No bootstrap records
or Workers are created by this document.

## Next design slices and open questions

Ordered by the decisions they unblock. These are implementation questions, not
another product interview.

1. **Board/Worker contract — owner: implementer/designer.** Write worked Quest,
   exp and execution records, the transition/authority matrix, brief/result
   formats, and the retry/fencing rules. Resolve result compatibility and
   invalidation before E0/E1; preserve the two-level planning vocabulary.
2. **Runtime and transport — owner: implementer.** Specify process ownership,
   singleton/fencing, Worker handshake, event cursors, acknowledgement stages,
   cancellation and limits. Test the actual pi interface rather than treating
   adapter documentation as an end-to-end guarantee. Select the core language
   here; OCaml/SQLite plus a thin pi adapter is the proposed starting point.
3. **Review and land transaction — owner: designer; human owns permission.**
   Define how deliberate human approval is recorded, its exact action scope,
   verifier authority, integration target policy, and the recovery journal.
   Recommend an explicitly named Quest integration branch; local land and
   external push are separately scoped actions. This gates E5, not a promise
   that worktrees enforce authorization against a hostile process.
4. **Queries and recaps — owner: designer with user evaluation.** Pin day/week
   windows, current-corrected versus historical semantics, traceability and
   the smallest useful output fixtures. Keep bp3 coordination projections and
   esc3 activity projections separate; both must be queryable, not only prose.

The next design pass should produce small worked records and failure traces
before detailed SQL, a full command catalog, or launcher extraction.

## Red chair record

- **User input:** strongest attack was optimizing "fewer edges" rather than
  understandability. The user clarified the requirement; the MVP now centers
  clear Quests/exps and separates that requirement from esc3's storage choice.
- **Problem space:** another Escapement rewrite or more parallel Workers could
  ship without reducing friction. Require a real-day useful recap and measure
  human attention against a simpler baseline, not only fixture parity.
- **Solution:** a CLI/worktree is not a security boundary, and a notification
  is not durable delivery. Carry forward explicit authority, atomic events,
  idempotency, ownership, independent receipts, and exact integration binding.
  The unresolved concrete mechanisms are gates in design slices 1–3, not
  implemented guarantees.
- **Milestones:** "use bp3 to build bp3" hides a bootstrap dependency; building
  four adapters or all of Escapement hides the riskiest useful slice. Make the
  temporary Worker-based bootstrap explicit, prove one real round-trip and
  idle/restart behavior, then drive esc3 through the resulting runtime.

## Handoff

This document authorizes no launch, merge, push, or external action. When the
implementation design is accepted, link the governing implementation packet
here and freeze the superseded proposed details. The packet governs execution
within this MVP scope; changes to agreed intent/scope remain explicit human
decisions. Do not maintain competing live designs or silently rewrite the
historical sketch.
