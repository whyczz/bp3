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
Quests and exps, delegates all coding execution to Workers, synthesizes
evidence, and owns landing mechanics. Workers land exps into a Quest branch
automatically under strict gates; the human steps in at Quest-to-main, where
they understand the integrated result and authorize promotion. Push needs its
own explicit scope.

Build the smallest reliable, single-host coordination loop, then use it to
build **bp3 itself**. esc3 is the follow-up transfer test, not the first
dogfood. Optimize for useful outcomes and human attention, not Worker count,
parallelism, or cheap tokens in isolation.

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
  logging but unused comparisons/metrics. Building bp3 with bp3 tests the
  coordination loop on real work; esc3 follows as a transfer test so a good
  self-dogfood is not mistaken for general proof.

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
3. **Delegation:** all coding work goes through an exp and a Worker, including
   small changes and one-off fixes. The Controller does not author code; it
   frames, delegates, reviews, synthesizes, and lands. Ceremony scales with
   blast radius, not diff size (see lanes below). The only direct-code
   exceptions are the hand-built genesis kernel and emergency repair when bp3
   or its launcher is down; both are logged and reconciled.
4. **Authority:** the human controls intent. An exp lands into its Quest
   branch automatically only when exact checks and independent review pass,
   the integration target is unchanged, the result kind satisfies its
   prerequisites, and budget remains. The human steps in at Quest-to-main to
   understand the integrated result and authorize promotion. Push is a
   separately scoped action; Quest-to-main approval does not imply it.
   Human touchpoints are Quest framing, Quest-to-main, and escalations
   (success-picture change, budget exhaustion, integration conflict, stale
   downstream results).
5. **Blockers:** every blocked Worker notifies the user through an IIUC-style
   recap, red-chaired next steps, and a recommendation.
6. **Waiting and multiplexing:** deterministic watchers, signals, timers, and
   long-polling are allowed. No model-driven polling or cron loops; routine
   notifications do not trigger model turns. Actionable events may trigger
   coalesced paid turns. The deterministic supervisor multiplexes 3-10 child
   processes; the Controller multiplexes decisions from Board snapshots, not
   by watching panes.
7. **Environment:** worktrees first, on one host, with SQLite and pi/Zellij.
   The codebase is OCaml, single-language; separate OS processes are fine.
   Colima/Docker or stronger isolation is a follow-up, not a claimed property.
8. **Dogfood:** bp3 builds bp3. First a hand-built genesis kernel (not claimed
   as dogfood), then bp3 coordinates its own features, then a one-week
   self-dogfood shakedown. esc3 is a follow-up transfer Quest. Projections
   mean recaps, not forecasts.
9. **Success:** the shakedown week produces accepted bp3 changes through bp3,
   independent checks, Controller restart recovery, a blocker briefing, no
   unreconciled target movement, and a prioritized hardening list. bp3 is
   adopted going forward; the week is a shakedown that prices friction, not
   an adoption trial against a predecessor.

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

Dependencies name the accepted results needed next, not a collection of vague
"related to" edges.

### Ceremony lanes

All coding goes to a Worker; the paperwork scales with blast radius and
reversibility, not lines changed. The user experiences a lane, not a form.

- **Micro lane:** one-line intent, auto-assembled brief, a warm Worker that
  already holds Quest context, deterministic checks, auto-land to the Quest
  branch, one-line notification. For contained, easily reversed changes.
- **Standard lane:** short brief with acceptance basis, Worker execution,
  independent review, auto-land. The default for normal features and fixes.
- **High-blast-radius lane:** auth, data migration, public API, concurrency,
  or anything hard to reverse. Design first, stronger review, explicit
  stopping conditions. A one-line auth change belongs here; a large generated
  fixture may not.

Deterministic mechanics — formatting, builds, test runs, Git operations —
are tooling or Controller verification, not model Worker work. Workers are
spawned per Quest and kept warm across its exps where context continuity
helps; each exp still gets its own worktree, branch, and execution record.
Independent review always uses a fresh execution, never the author's.

### One-off fixes

A one-off is a taxi ride, not a Quest ceremony. Board records are still
created for provenance, but the user sees only: request, patch, evidence,
decision.

- Inside an active Quest, a one-off attaches as a micro-exp.
- With no active Quest, bp3 creates a hidden single-exp Quest. Its exp
  auto-lands to the integration branch; the human does a proportionate
  Quest-to-main review of the final diff.
- Urgent breakage expedites the same path; it does not preempt or kill
  unrelated running Workers unless the user says so.
- A read-only investigation is a scout execution returning a report; no
  patch or landing follows unless it becomes an exp.
- Do not accumulate one-offs in a standing miscellaneous Quest. Batch only
  independent one-offs the user deliberately promotes together, so the
  Quest-to-main review stays comprehensible.

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

Every exp auto-land posts a compact notice to the main session: Quest and exp,
integration commit, one-line outcome, check and review verdicts, files touched,
exps unblocked or staled, and a revert handle. Notices inform; silence is never
consent, and a notice is not an approval request. Notices may be coalesced for
display, but none is dropped; blockers and escalations interrupt instead of
waiting for the next digest.

Quest-to-main is a comprehension gate, not a rubber stamp on a raw diff. The
Controller presents a promotion packet: a runnable demo with observed output,
a diff tour ordered by concept (what changed and why), check receipts bound to
the exact integration commit, risks and limitations, the auto-land log,
superseded or excluded results, and a rollback plan. Any change after review
invalidates the packet and regenerates it. If a Quest grows past what the
human can understand in one sitting, the Controller splits it before the gate.

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

**Settled:** the codebase is OCaml, single-language, preserving the
predecessor's OCaml/SQLite core. The pi adapter crosses an explicit process
or IPC boundary from OCaml; if pi only offers an in-process SDK in another
language, that fact must surface in the pre-implementation spike, not after
the core is built. One codebase does not require one OS process: CLI,
supervisor, and bridge may be separate executables from the same source.

**Recommended runtime ownership:** a deterministic local supervisor owns
reconciliation, event following, liveness, and enforced limits even when the
Controller model is idle or its session exits. A thin pi bridge displays
notifications and requests actionable turns. The supervisor is not another
LLM Controller and cannot invent work or approval. Its precise lifetime,
singleton claim, and reconnect protocol are the second design slice below.

### Multiplexing 3-10 Workers

The supervisor multiplexes processes; the Controller multiplexes decisions.
The supervisor tracks the live roster — panes, heartbeats, worktrees,
resource namespaces, deaths, restarts — for 3-10 concurrent children,
reviewers included. The Controller never watches panes or holds every
Worker's context. On an actionable wake it reads one compact control
snapshot from the Board: needs-decision (blockers, escalations), ready
(candidates passing checks), running (exp, elapsed, last meaningful event,
budget consumed), failed or stale, and capacity (free slots, review and
integration backlog). Full transcripts stay behind references.

Launch is gated by backpressure, not by free slots alone:

- Ramp concurrency during dogfood: start at 3, expand to 5, then toward 10
  only while review and integration keep up.
- Stop launching when the review backlog grows, even with free Worker slots.
  Reserve reviewer capacity; a proposed starting split is eight execution
  and two review slots, borrowed dynamically when one side idles.
- Serialize integration per Quest branch; individually passing branches can
  still fail composed.
- Priority order: unblock a human or a dependency chain, finish nearly
  complete work, review and land completed candidates, start new independent
  work, then speculative work. One-offs take the next free slot without
  killing running Workers.
- Assign resource namespaces (ports, test databases, caches, temp dirs) so
  parallel test runs do not fight over one host's shared state.
- Consolidate common blockers: if several Workers raise the same underlying
  question, it becomes one decision, not four conversations.
- Liveness means meaningful-event freshness, not a heartbeat alone; a live
  process with no useful progress is a zombie to be reconciled.

### Data models

Logical records and the fields that matter; exact tables and state enums remain
to be designed. Avoid a universal node/edge store for this control plane.

| Record | Responsibility and essential data |
|---|---|
| Quest | Intent, why, success picture, constraints, state, human acceptance, optional prior-result provenance. |
| exp | Quest ID, versioned brief, bounded contribution, expected result kind, acceptance basis, prerequisites, limits, selected result, disposition, ceremony lane. |
| Execution | Exp ID, role, ownership generation, immutable brief/input revisions, harness/model/version, workspace, endpoint/session, desired state and observed liveness, intended file scope, resource namespace, warm-session reference. |
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
- An auto-land notice is not an approval request, and silence after a notice
  is not consent for Quest-to-main or push.

### Functions and Worker protocol

Names describe responsibilities, not implemented command spellings.

| Operation | Responsibility and failure behavior |
|---|---|
| Define/amend Quest or exp | Record intent and explicit revisions; reject invalid dependencies; identify consequences for existing executions/results. |
| Launch | Assign the ceremony lane; validate scope, prerequisites and capacity (3-10 child cap, reviewer reserve, review-backlog backpressure); warn on likely file-scope overlap; reserve execution ownership; freeze inputs; prepare worktree and resource namespace; start and handshake from the actual Worker environment. Reconcile partial launch instead of blindly retrying it. |
| Report / ask / reply | Persist progress, blockers, candidates, and answers with stable identities. Workers cannot accept their own result or authorize land through reporting operations. |
| Review | Dispatch independent inspection/check execution against exact outputs; retain receipts and return a bounded review packet to the Controller. |
| Prepare / auto-land / promote | Compose and check the actual integration. Exp-to-Quest-branch land is automatic when the authority gates pass, followed by a compact main-session notice. Quest-to-main requires the human comprehension packet and explicit authorization, and conditionally updates only the authorized target. Journal partial progress for recovery. |
| Context / query / recap | Return the compact control snapshot and current coordination and evidence references, including unresolved obligations; full transcripts are fetched only when needed. |
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
decisions, next actions, and available cost/attention observations, including
ceremony cost per lane (intent-to-spawn latency, Controller framing and review
turns versus Worker execution time) and every manual bypass. The control
snapshot and the Quest-to-main promotion packet are projections of the same
records, not second sources of truth. For the follow-up esc3 Quest, recaps
cover recorded activity, plans, contexts/goals, and metrics. These are
separate domains/stores, not a shared generic graph schema. Historical
"as known then" versus current-corrected views must be specified rather than
silently conflated.

No SQLite transaction spans a process launch, Git command, or model call.
Backups use a consistent SQLite snapshot plus referenced Git/artifact objects;
a casual copy of a live database is not a restore contract. Version migrations
and test restore in a fresh location.

**Self-hosting:** because bp3 builds bp3, the running system is always the
last promoted build. Workers edit only the next build in worktrees; candidate
changes are tested against a scratch copy of the Board, never the live Board.
Promotion is an explicit Quest-to-main act: candidate build, checks on a Board
copy, human acceptance, atomic switch with a retained rollback build. A bad
exp must never be able to corrupt the coordinator that would repair it; if it
does, the emergency direct-repair exception applies and is reconciled into
the Board afterward.

### Interfaces, authority, and failure modes

**Cooperative worktrees, not hostile-code isolation.** Workers and check runners
may share filesystem access, Git metadata, credentials, and network access.
Controlled operations prevent protocol mistakes; they do not prevent an
unrestricted same-user process from bypassing them. A local service alone would
not fix that. Do not claim a sandbox or safe execution of hostile checks.

Run independent checks in a separate verifier environment with the narrowest
practical authority, not inside the Controller session merely because a Worker
supplied a command. The later isolation exp must cover both Workers and check
runners. The concrete human approval entry path for Quest-to-main remains a
pre-promotion design gate; a model-supplied `actor=human` field is not proof
of permission. Because worktrees are cooperative, bypass of the protocol by a
same-user process cannot be prevented; it must be detectable — target-branch
movement without a matching Board journal is an unreconciled-landing incident.

Authority tiers:

- **Worker commits** in its own worktree and branch: automatic, no gate.
- **Exp-to-Quest-branch land:** automatic when deterministic checks and
  independent review pass on the exact integration, the target is unchanged,
  the result kind satisfies prerequisites, and budget remains. Followed by
  the compact main-session notice. Auto-land changes who signs, not what is
  verified.
- **Quest-to-main promotion:** human, via the comprehension packet, bound to
  the exact checked integration commit.
- **Push or publishing:** separately scoped human authorization; neither
  auto-land nor Quest-to-main approval implies it.

Proposed land transaction (both tiers): record expected target **B**,
construct integration commit **I**, check **I**, apply the tier's authority
(auto-gates or human authorization for the exact action/target and **I**),
then conditionally update the target only if it still equals **B**. Persist
enough journal state to reconcile a crash between Git and SQLite. Target
movement requires re-preparation and, for promotion, renewed authorization.

| Failure | Required containment |
|---|---|
| Lost response / duplicate report | Replay the committed operation outcome; do not duplicate results or obligations. |
| Competing Controllers / stale Worker | Conditional revisions and ownership generations prevent conflicting reservations or stale mutations. |
| Launch or integration crash | Durable stages and reconciliation discover what happened before retrying side effects. |
| Missed notification / watcher death | Board obligations survive; reconnect and replay discover them. Distinguish recorded, transport accepted, observed, and handled. |
| Busy or permission-blocked harness | Preserve pending delivery; acceptance by transport is not evidence of a model turn or user acknowledgement. |
| Capacity or budget exhaustion | Defined stop/escalation behavior, independent of model polling. Unknown cost is reported unknown, not zero. Auto-land never expands its own budget. |
| Output changes after check/approval | Reject mismatched or stale review/authorization; check the actual combined integration. |
| Thundering herd / review saturation | Backpressure stops new launches; completed candidates queue with receipts instead of flooding the Controller or the user. |
| Common blocker across Workers | Consolidate into one Board question and one human decision; do not run parallel conversations about the same unknown. |
| Overlapping Worker scope | Intended-scope records warn before launch; integration still checks the composed result, and conflicts escalate instead of auto-landing. |
| Zombie Worker | Meaningful-event staleness triggers reconciliation; a live process or fresh heartbeat alone does not count as progress. |
| Coordinator self-corruption | Running build is the last promoted build; candidate work is tested on a Board copy; rollback build retained; emergency direct repair is logged and reconciled. |
| Unreconciled target movement | Detect branch movement without a Board journal, freeze further auto-land on that target, and surface it as an incident; never silently adopt it. |

## Scope boundaries and alternatives

In: one host, one OCaml codebase/CLI, SQLite, pi/Zellij, worktrees, bounded
Worker briefs, ceremony lanes, one-off taxi lane, 3-10 child multiplexing with
backpressure, durable reports/questions, deterministic waiting, independent
review, gated auto-land to Quest branches, human Quest-to-main promotion,
recovery, self-hosting safeguards, and queryable evidence-backed recaps.
Retain small-scale fan-out/fan-in without building a general scheduler.

Not required for the MVP:

- A Task/Milestone planning hierarchy, universal graph engine, or workflow DSL.
- Four production harness integrations, remote Workers, a web UI, or immediate
  extraction into separate Controller/Worker/launcher products.
- Colima/Docker isolation, hostile-Worker security claims, or unrestricted
  external actions. Isolation remains a follow-up, not a dismissed risk.
- Automatic reruns of stale descendants, automatic Quest-to-main promotion,
  automatic push, forecast engines, archive mining, or model-routing
  optimization before end-to-end value exists.
- esc3. It is the follow-up transfer Quest, not MVP dogfood.

Adoption is settled: bp3 is the way forward, with no predecessor fallback.
That does not exempt it from measurement. Track human attention, ceremony
cost per lane, bypasses, and rework across the shakedown week; cut lanes,
gates, or reports that cost attention without buying recovery, evidence, or
outcomes. Evaluate targeted protocol patterns rather than importing an entire
orchestration platform. More parallelism is not itself an acceptance test.

## bp3 dogfood: bp3 builds bp3

The first dogfood is bp3 implementing its own follow-on features. This tests
the coordination loop on real, consequential work without confounding it with
a second product's design. It also creates the central self-hosting risk,
handled above: the running bp3 is always the last promoted build, Workers
edit only the next build, and candidates rehearse against a Board copy.

Sequence:

1. **Genesis kernel, hand-built.** Minimal OCaml CLI and Board, immutable
   brief, one real pi Worker round-trip. This is an exception in transport,
   not dogfood, and is never described as bp3 building itself.
2. **First self-hosted change.** bp3 coordinates one small real bp3 feature
   end-to-end: Worker implementation, independent review, auto-land to the
   Quest branch with its main-session notice, human Quest-to-main promotion,
   and one deliberate Controller kill mid-flight.
3. **One-week shakedown.** All bp3 development goes through bp3. Before day
   one, write down the scorecard: accepted, reworked, and blocked exps;
   human-active minutes per accepted change; interventions and repeated
   explanations; ceremony cost per lane; Controller restarts and their
   recovery; manual bypasses (target zero unreconciled); blockers and their
   resolution path. If bp3 is down, work directly to unblock, log it as an
   incident, and reconcile it into the Board afterward — commitment to bp3
   does not mean work stops when the coordinator does.
4. **Hardening list.** The week's output is a prioritized list of keep, cut,
   and fix decisions, each tied to a logged incident or measurement. A lane
   whose framing and review cost more Controller turns than its Workers spend
   executing is too heavy and gets loosened.

Do not call the genesis kernel, or any direct Controller-written code outside
the logged emergency exception, "bp3 dogfood." Self-dogfood success is also
not general proof: bp3-shaped work (OCaml, tests, docs, small exps) is the
home fixture. esc3 is the away fixture.

### Follow-up: esc3 transfer Quest

After the shakedown and hardening, drive one esc3 Quest through bp3 as the
transfer test. Use esc2's implemented MVP as the behavioral reference, not a
requirement to copy its schema or preserve known reporting defects. Its
capabilities include plan/done capture, temporal nesting, contexts, tags,
declared metrics, corrections/history/provenance, plan copying,
comparison/rollups, and text/JSON operation surfaces; any staged parity
deferral must be explicit, not silently omitted. Add queryable daily/weekly
recaps with concrete records and fixtures (nesting, overlaps, midnight,
corrections, missing-data versus zero, multi-goal accounting where elapsed
time must not multiply). Use a new project/database; leave esc2 data intact.
The broader Python/web/auth/audio Escapement application is not the scope.

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
| Review and authorized land | Independent checks bind to the actual integration; exp auto-land fires only when every gate passes and posts its notice; Quest-to-main refuses absent, mismatched, or stale human authorization and target movement. Crash recovery reconciles Git and Board; branch movement without a journal is detected and frozen, never silently adopted. |
| Limits and restore | Exhaust a configured limit; interrupt the runtime; restore Board plus referenced artifacts in a fresh location without lost or silently resumed obligations. |
| Lanes and one-offs | A micro one-off goes from request to evidence-backed patch with no Quest conversation; a one-line high-blast-radius change is forced into the high lane; deterministic mechanical changes run without a model Worker. Per-lane ceremony cost is recorded. |
| Multiplexing | Run 3, then 5, then 10 concurrent children including reviewers; review saturation stops new launches; a common blocker consolidates into one question; overlapping scopes warn before launch; resource namespaces keep parallel test runs apart; a snapshot after Controller restart reconstructs the full roster. |
| Notice and promotion packet | Every auto-land produces exactly one main-session notice with a revert handle; silence is never treated as consent. The Quest-to-main packet explains the integrated diff by concept, binds receipts to the exact commit, and is invalidated by any later change; an oversized Quest is split before the gate. |
| Self-hosting | A Worker exp that would corrupt the Board, launcher, or land path is caught on a Board copy; the running build is unaffected; promotion switches atomically and rollback restores the prior build. |
| Useful dogfood | bp3 builds bp3 through the one-week shakedown; the user gets inspectable accepted changes, the scorecard, and a hardening list without manual scheduling. esc3 transfer is a later, separate check. |

Measure human active time, interventions/repeated explanations, accepted
outcomes, useful learning, elapsed time, ceremony cost per lane, and total
model/check/rework cost. Unavailable measurements remain explicit. A low
token bill with more human babysitting is not success; because adoption is
settled, report these as friction to fix, not as an adoption verdict.

## Proposed delivery milestones

These are design-stage experiment proposals, **not created Board records or a
new Milestone entity**. Scope each exp around an inspectable output.

| Exp | Shippable output and decisive check | Depends on |
|---|---|---|
| G0 — Genesis kernel and pi spike | Hand-built minimal OCaml CLI/Board plus proof, from OCaml, that a real pi Worker handshakes in a worktree, reads an exact brief, and reports a blocker/candidate. Surfaces the true pi boundary before the core grows. Not dogfood. | None |
| E0 — Protocol counterexamples | Small transition/identity contract with executable fixtures for retries, ownership, result kinds, and races; each disputed transition has an expected outcome. | Worked records from design slice 1 |
| E1 — Worker reaches Board | Genesis kernel plus immutable brief, blocker/candidate report, retry check, and one micro-lane one-off end-to-end (request, patch, evidence, decision). | G0, E0 |
| E2 — Tokenless waiting and multiplexing | Deterministic runtime/pi bridge and supervisor roster for 3 concurrent children; idle, busy, restart, permission-wait and watcher-death traces meet the notification contract; control snapshot reconstructs the roster. | E1 |
| E3 — Crash/replacement | Interrupt launch/report boundaries; competing Controllers and resumed old Workers cannot duplicate or corrupt committed work. | E1–E2 |
| E4 — Evolving lineage | Executable fan-out/fan-in, pin, amendment, negative-finding and withdrawal cases; incompatible inputs fail before dispatch. | E1, E0 lineage rules |
| E5 — Review, auto-land, promotion | Independent verification, gated exp auto-land with main-session notice, human comprehension packet and exact-commit Quest-to-main, Git/Board crash reconciliation, and self-hosting promotion/rollback on a scratch repo. | E1, E3–E4 |
| E6 — Self-hosted bp3 and shakedown week | First self-hosted bp3 feature, concurrency ramped 3 to 5 to 10 under backpressure, then the one-week all-bp3-through-bp3 shakedown with the pre-registered scorecard, a forced blocker, a Controller restart, limits, and fresh-location restore. | E2–E5 |
| E7 — Harden, then transfer | Prioritized keep/cut/fix list from the shakedown; loosen any lane whose ceremony exceeds its execution value; then run the esc3 transfer Quest as the away fixture. | E6 scorecard |

Prioritize the G0 spike, E0, E1, and pi-only E2. E0 must stay small and feed
the real round-trip, not become months of abstract protocol design. Other
harnesses and isolation can be subsequent exps without blocking proof of the
cooperative pi workflow.

**Bootstrap:** the genesis kernel replaces the earlier temporary-file-ledger
proposal. It is hand-built directly, kept deliberately Board-shaped, and its
construction decisions are recorded as the first Board records once it runs.
The first genuinely Worker-built, reviewed, and promoted change is the start
of dogfood. No bootstrap records or Workers are created by this document.

## Next design slices and open questions

Ordered by the decisions they unblock. These are implementation questions, not
another product interview.

1. **Board/Worker contract — owner: implementer/designer.** Write worked Quest,
   exp and execution records, the transition/authority matrix, brief/result
   formats, and the retry/fencing rules. Resolve result compatibility and
   invalidation before E0/E1; preserve the two-level planning vocabulary.
2. **Runtime and transport — owner: implementer.** Specify process ownership,
   singleton/fencing, Worker handshake, event cursors, acknowledgement stages,
   cancellation and limits, the 3-10 roster and backpressure rules, and the
   control snapshot format. Test the actual pi interface from OCaml rather
   than treating adapter documentation as an end-to-end guarantee; the core
   language is settled as OCaml.
3. **Review, land, and promotion — owner: designer; human owns Quest-to-main.**
   Define the auto-land gates and notice, how deliberate human promotion is
   recorded, its exact action scope, the comprehension packet and Quest-size
   budget, verifier authority, integration target policy, the recovery
   journal, and self-hosting promotion/rollback. Recommend an explicitly named
   Quest integration branch; promotion and external push are separately scoped
   actions. This gates E5, not a promise that worktrees enforce authorization
   against a hostile process.
4. **Queries and recaps — owner: designer with user evaluation.** Pin day/week
   windows, current-corrected versus historical semantics, traceability, the
   shakedown scorecard fields, and the smallest useful output fixtures. Keep
   bp3 coordination projections and the later esc3 activity projections
   separate; both must be queryable, not only prose.

The next design pass should produce small worked records and failure traces
before detailed SQL, a full command catalog, or launcher extraction.

## Red chair record

- **User input:** strongest attack was optimizing "fewer edges" rather than
  understandability. The user clarified the requirement; the MVP now centers
  clear Quests/exps and separates that requirement from esc3's storage choice.
- **Problem space:** another Escapement rewrite or more parallel Workers could
  ship without reducing friction. The user settled this: bp3 builds bp3 first,
  esc3 is the later transfer test, and adoption is not on trial. Measure human
  attention, ceremony per lane, and bypasses during the shakedown week and cut
  whatever does not buy recovery, evidence, or outcomes.
- **Solution:** a CLI/worktree is not a security boundary, and a notification
  is not durable delivery. Carry forward tiered authority (gated auto-land to
  Quest branches, human comprehension-gated Quest-to-main, separately scoped
  push), atomic events, idempotency, ownership, independent receipts, exact
  integration binding, and unreconciled-movement detection. The unresolved
  concrete mechanisms are gates in design slices 1–3, not implemented
  guarantees.
- **Milestones:** "use bp3 to build bp3" hides a bootstrap dependency and a
  self-corruption risk; building four adapters or all of Escapement hides the
  riskiest useful slice. Make the hand-built genesis kernel and the
  stable-host/promotion split explicit, prove one real round-trip and
  idle/restart behavior, multiplex 3-10 children under backpressure, then run
  the shakedown week before the esc3 transfer.

## Handoff

This document authorizes no launch, merge, push, or external action. When the
implementation design is accepted, link the governing implementation packet
here and freeze the superseded proposed details. The packet governs execution
within this MVP scope; changes to agreed intent/scope remain explicit human
decisions. Do not maintain competing live designs or silently rewrite the
historical sketch.
