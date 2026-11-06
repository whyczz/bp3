# bp3 MVP: understandable coordination, useful delivery

Status: **MVP scope agreed; Exp 1 genesis acceptance passed.**
The [genesis exp record](../exp/2026-11-05-genesis.md) resolves the Exp 1 subset
of the proposals below and holds its runbook and observed evidence. See the
[active Quest](../quests/2026-11-05-bp3-mvp.md). Review/land/promotion and the
broader runtime features remain proposed, not implemented guarantees. The
[Exp 2 record](../exp/2026-11-05-auto-land.md) records the next
integration design and the authorized genesis source-checkpoint handoff.

This document is the current MVP scope. It supersedes the
[original architecture sketch](bp3-control.md) where they differ. The sketch
is retained as background, not as a second specification. Product decisions
below are agreed; implementation proposals and open questions are labeled.

## TL;DR

Help the user **learn more and deliver more with less time and higher-signal
human input/output**. The user directs intent; a lightweight Controller frames
Quests and exps, delegates all coding execution to Workers, synthesizes
evidence, and owns landing mechanics. Exps land into a Quest branch
automatically under strict gates; the human steps in at Quest-to-master, where
they understand the integrated result and authorize promotion. Push needs its
own explicit scope.

Build the smallest reliable, single-host coordination loop, then use it to
build **bp3 itself**. esc3 follows as Quest 2, a separate one-week
build-out, not the first dogfood. Optimize for useful outcomes and human attention, not Worker count,
parallelism, or cheap tokens in isolation.

## ELI5

A Quest says what we want and why. An exp says what useful thing to try next
and how we will judge it. Workers do the work. The Board remembers what they
were told, what happened, and what remains unresolved. You get a short briefing
and a recommendation when your judgment is needed, not a scheduling job.

## Context

The repository at `2c8a08654d0d5fde83052c7fef3f1a04283a409b` contained only
`readme.md` and the architecture sketch. At that design baseline there was no
runtime to claim reliable. This MVP records the subsequent review and user
clarification; current implementation evidence is linked above.

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
  coordination loop on real work; esc3 follows as Quest 2 so a good
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
   branch automatically only when its lane's gates pass — deterministic
   checks for the micro lane, checks plus independent review for standard
   and high-blast-radius lanes — the integration target is unchanged, the
   result kind satisfies its prerequisites, and budget remains. Every
   auto-land emits an IIUC/TL;DR land report (below) and moves the exp to
   the `auto_landed` state. The human steps in at Quest-to-master to
   understand the integrated result and authorize promotion. Push is a
   separately scoped action; Quest-to-master approval does not imply it.
   Human touchpoints are Quest framing, Quest-to-master, and escalations
   (success-picture change, budget exhaustion, integration conflict, stale
   downstream results).
5. **Blockers:** every blocked Worker notifies the user through an IIUC-style
   recap, red-chaired next steps, and a recommendation.
6. **Waiting and multiplexing:** deterministic watchers, signals, timers, and
   long-polling are allowed. No model-driven polling or cron loops; routine
   notifications do not trigger model turns. Actionable events may trigger
   coalesced paid turns. The deterministic runtime multiplexes 3-10 child
   processes; the Controller multiplexes decisions from Board snapshots, not
   by watching panes.
7. **Environment:** worktrees first, on one host, with SQLite and pi/Zellij.
   The codebase is OCaml, single-language; separate OS processes are fine.
   One monorepo named **bp3** holds core, plugins, Board-coupled control
   skills, and all design docs (see Repository shape below); the generic
   bp3-yap-skills library stays a separate repo. Colima/Docker or stronger
   isolation is a follow-up, not a claimed property.
8. **Dogfood:** two Quests, specced below. Quest 1 proves the loop on bp3
   itself (genesis kernel, then exps 1-3) with a toy fixture as the permanent
   conformance target. Quest 2 is the one-week esc3 MVP build-out, run
   entirely through bp3, with the toy template as its daily dogfood gate and
   cross-repo checks between bp3 and esc3. Projections mean recaps, not
   forecasts.
9. **Success:** Quest 1 ends with a self-hosted, human-promoted bp3 change,
   Controller restart recovery, blocker briefings, and no unreconciled target
   movement. Quest 2 ends with a usable esc3, the week's scorecard, and a
   prioritized hardening list. bp3 is adopted going forward; measurement
   prices friction, it is not an adoption trial against a predecessor.

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
  branch, land report. For contained, easily reversed changes. This lane is
  the explicit checks-only exception to the independent-review gate; the
  land report and revert handle are its audit trail.
- **Standard lane:** short brief with acceptance basis, Worker execution,
  independent review, auto-land with land report. The default for normal
  features and fixes.
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
  Quest-to-master review of the final diff.
- Urgent breakage expedites the same path; it does not preempt or kill
  unrelated running Workers unless the user says so.
- A read-only investigation is a scout execution returning a report; no
  patch or landing follows unless it becomes an exp.
- Do not accumulate one-offs in a standing miscellaneous Quest. Batch only
  independent one-offs the user deliberately promotes together, so the
  Quest-to-master review stays comprehensible.

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

Every exp auto-land posts a compact land report to the main session, in
IIUC/TL;DR style:

- **TL;DR:** one line — what landed and why it matters.
- **IIUC:** the intended outcome from the brief, and what the Worker actually
  did against it.
- **Demos:** the demo or smoke command run, with observed output or a link
  to it; "none" is stated, never implied.
- **Tests:** check and (per lane) review verdicts with receipts, including
  failures that were waived and by what rule.
- **Code pointers:** integration commit, Quest/exp/execution IDs, files and
  key functions changed, exps unblocked or staled, and a revert handle.

Reports inform; silence is never consent, and a report is not an approval
request. Reports may be coalesced for display, but none is dropped; blockers
and escalations interrupt instead of waiting for the next digest. The report
is stored on the integration record, which carries the exp's `auto_landed`
state (see Data models).

Quest-to-master is a comprehension gate, not a rubber stamp on a raw diff. The
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

Keep one CLI/codebase — the bp3 monorepo — with separate internal modules
for operations, storage, launch, runtime, and integration. Start with pi; do
not implement four production harness adapters before proving one.

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
predecessor's OCaml/SQLite core. The pi adapter is a bridge extension inside
the Worker's pi session (see Small runtime below), not a second language
core; if pi's extension surface cannot carry it, that fact must surface in
the Exp 1 spike, not after the core is built. One codebase does not require
one OS process: CLI, runtime, and bridge may be separate executables from
the same source.

**Recommended runtime ownership:** the deterministic local runtime owns
reconciliation, event following, liveness, and enforced limits even when the
Controller model is idle or its session exits. A thin pi bridge displays
notifications and requests actionable turns. The runtime is not another
LLM Controller and cannot invent work or approval. Its precise lifetime,
singleton claim, and reconnect protocol are the second design slice below.

### Small runtime, not a fortress

FirstMate supervises a visible crew with a large bash estate because it
owns neither the harness nor the state: many backends, status-log files,
and pane-hash classification. bp3 owns one harness first and one Board, so
the same visible, drivable crew is four pieces:

- **core/runtime** — one OCaml process: spawn (worktree + Zellij pane + pi
  with the bridge loaded), roster, a local signal socket, reconciliation.
- **plugins/harness-pi/bridge** — one TypeScript extension file inside the
  Worker's pi. It registers with the runtime, receives wake/steer over the
  socket, injects via `pi.sendUserMessage`, and emits honest signals:
  session ready, turn settled (`agent_settled`/`isIdle`, never `agent_end`),
  permission prompt, exited, and `took_over` when an `input` event arrives
  interactively instead of from the runtime.
- **core/board** — SQLite holds briefs, reports, the steering inbox, and
  signals. Content moves as data, never as keystrokes.
- **Zellij** — pixels and keyboard only. Each Worker is a real TUI in its
  own pane: the user can watch it, and typing in the pane is takeover.

Rules that keep it small:

- The runtime never reads pane text to decide anything. `dump-screen` is
  forbidden as a state source; a human-facing `bp3 peek` may show a pane,
  machines do not get to. Anything that would need screen classification
  must become a bridge signal instead.
- Briefs, answers, and steering are Board records delivered by the runtime;
  Workers report by running `bp3` ops (`report`, `block`, `finish`) from
  their own shell, not by declaring status lines for a watcher to parse.
- Steering is durable first (`bp3 steer` writes the inbox), then delivered
  (bridge `sendUserMessage` as steer/followUp). Delivery is proven by
  bridge/turn signals, not by pane change.
- Bridge size discipline: roughly 200 lines. Growth past that means policy
  is leaking out of core. No backend abstraction until a second backend
  exists; Zellij calls are just Zellij calls. The skipped FirstMate mass —
  multi-backend adapters, secondmates, forge integrations, relay, project
  modes, pane-hash classifiers — is out of scope by name, not by accident.
- Fallback, stated honestly: if the bridge cannot carry brief, blocker, and
  settled-idle signals in the Exp 1 spike, Workers run owned-process RPC
  (`pi --mode rpc`) for Quest 1 and live view/drive becomes the harness
  exp's acceptance test instead of a claim.

### Repository shape: one monorepo named bp3

Settled: there is one repo, **bp3**, reached by git-renaming the current
bp3-control repo (history and docs move with it; no new repo is created and
no design is re-homed by hand). Inside it, a **core/plugins** split: the
irreducible coordination loop is core; everything replaceable is a plugin.
The earlier launcher-repo and worker-repo proposals in bp3-docs are module
designs inside bp3, not separate repositories; bp3-docs remains provenance.
One exception stays separate by design: **bp3-yap-skills**, the generic,
harness-portable skill library, is its own repo. bp3 keeps only the
Board-coupled control skills and the harness packaging that wires skills
into a Controller session.

```text
bp3/
  core/protocol/   packet schema, ops types, shared IDs (the contract)
  core/board/      SQLite store, state machines, migrations
  core/control/    ops CLI, Controller context, review, land, promotion
  core/runtime/    roster, event following, liveness, backpressure,
                   plugin host
  plugins/harness-pi/       first real plugin (intents/signals adapter)
  plugins/harness-Muse/   second adapter, gated by conformance
  plugins/packs/            expert packs and routed Worker content
  plugins/warden-*/         future: event consumers that flag and question
  plugins/cron-*/           future: obligation/timer sources only
  skills/          project skill sources (quest + Board-coupled control skills)
  docs/            this MVP, the historical sketch, imported provenance
  docs/quests/     one file per Quest: <date>-<slug>.md
  docs/exp/        one detailed record per exp: <date>-<slug>.md
```

**Project skills install, explicit when working in bp3:** skill sources
live in `skills/<id>/SKILL.md` as plain Markdown — no templating in bp3;
skills are invoked by name (`/quest`, `$quest` is harness UI, not skill
content). `bp3 skills install --harness=<pi|claude|codex|muse|all>`
copies each source into that harness's project skill dir (`.pi/skills`,
`.claude/skills`, `.agents/skills`) with a GENERATED notice. Rendered
files are generated — edit the source and re-run. `/quest` is a bp3
project skill and ships this way; the generic bp3-yap-skills library
remains the separate personal layer.

**Quest file convention, explicit when working in bp3:** every Quest gets
exactly one human-facing file at `docs/quests/<date>-<slug>.md` in its home
repo (`<date>` as `YYYY-MM-DD`, `<slug>` short lowercase kebab-case), written
with the `$quest` skill — TL;DR, ELI5, goal, success picture, scope, human
touchpoints, exps with acceptance checks, scorecard, red chair. The file is
the record humans read and approve; the Board is the runtime truth once
implementation exists. Cross-repo Quests keep their file in their home repo
(the esc3 Quest's file lives in esc3), never copied into bp3.

**Exp record convention:** detailed mini-designs, code tours, acceptance evidence
and runbooks live together at `docs/exp/<date>-<slug>.md`, one canonical record
per exp, linked from its parent Quest. The Quest retains ordering, dependencies,
intent and the acceptance summary; the exp file is not another plan or Board.
`bp3-writer` owns this format and evidence discipline; an explicitly requested
`anon-writer` may supply voice/OODA presentation. Cross-exp architecture remains
in `docs/designs/`. Neither writer authorizes execution, landing or promotion.

Core is what bp3 cannot run without: protocol, board, control, runtime.
Spawn mechanics live in runtime for the MVP; harness-specific adapters sit
under it as plugins. Worker brief/finish is a protocol client, so
core-adjacent; the packs it routes are plugin content.

Plugin rules, settled with the layout:

- Plugins never write the Board directly and never spawn work on their own.
  They emit signals and call the same ops as every other caller; control
  disposes. A plugin is never a second control plane.
- The runtime hosts plugins: per-plugin event cursors, idempotent delivery,
  a disable switch instead of restart loops, and no plugin-private durable
  state — anything that matters goes through ops into the Board.
- v1 plugins are compile-time OCaml modules behind a registry, toggled by
  config. No dynamic loader. Out-of-process plugins (Board events over a
  socket, crash-isolated) arrive only if a plugin needs untrusted code.
- The plugin seam is proven by the harness adapters first (pi, then Muse
  under the ControllerAdapter conformance suite), not designed for
  hypothetical wardens. Warden and cron plugins inherit that seam.
- A cron plugin may only create Board obligations and timers. It can never
  wake a model directly; the runtime still decides what becomes a coalesced
  actionable wake, per the tokenless-waiting contract.

Why one repo: the packet/ops contract will churn during dogfood, and one
commit must be able to change its producer and consumers together; bp3
builds bp3 in the same tree it coordinates; one user, one host, and one
language have no release-independence problem to solve. Module boundaries
are the discipline instead: cross-module calls go through the protocol and
Board operations, never around them.

Split a module into its own repo only when a trigger fires: a second
harness or non-bp3 caller needs it independently, a real privilege boundary
appears (for example launcher-held credentials), or release cadences
genuinely diverge. bp3-yap-skills already meets that bar — generic skills
serve many harnesses and hosts — which is why it stays separate. Until a
trigger fires inside bp3, separate launcher/worker/control repos are
explicitly not required.

### Multiplexing 3-10 Workers

The runtime multiplexes processes; the Controller multiplexes decisions.
The runtime tracks the live roster — panes, heartbeats, worktrees,
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
| exp | Quest ID, versioned brief, bounded contribution, expected result kind, acceptance basis, prerequisites, limits, selected result, disposition and state (including `auto_landed`), ceremony lane. |
| Execution | Exp ID, role, ownership generation, immutable brief/input revisions, harness/model/version, workspace, endpoint/session, desired state and observed liveness, intended file scope, resource namespace, warm-session reference. |
| Result | Execution ID, exact output commits/artifacts, result kind, evidence claims, limitations; useful findings need no fabricated merge. |
| Review | Exact result/brief, independent reviewer or verifier execution, check receipts, findings, verdict. Worker claims remain separate from verifier receipts. |
| Question/reply | Execution and question identity, blocker, answer/decision reference, delivery and handling state. |
| Approval/integration | Land kind (auto or human-promoted), land report (TL;DR, IIUC, demos, tests, code pointers), human decision reference where required, exact authorized action/target/revision, expected target commit, checked integration commit, resulting state, durable operation journal. |

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
- An auto-land report is not an approval request, and silence after a report
  is not consent for Quest-to-master or push.
- `auto_landed` is a distinct exp state: the selected result is integrated
  into the Quest branch and carries its land report. It is not human
  acceptance, not Quest completion, and not promotion to master; reverting an
  auto-land returns the exp to an explicit non-landed disposition without
  erasing the report.

### Functions and Worker protocol

Names describe responsibilities, not implemented command spellings.

| Operation | Responsibility and failure behavior |
|---|---|
| Define/amend Quest or exp | Record intent and explicit revisions; reject invalid dependencies; identify consequences for existing executions/results. |
| Launch | Assign the ceremony lane; validate scope, prerequisites and capacity (3-10 child cap, reviewer reserve, review-backlog backpressure); warn on likely file-scope overlap; reserve execution ownership; freeze inputs; prepare worktree and resource namespace; start and handshake from the actual Worker environment. Reconcile partial launch instead of blindly retrying it. |
| Report / ask / reply | Persist progress, blockers, candidates, and answers with stable identities. Workers cannot accept their own result or authorize land through reporting operations. |
| Review | Dispatch independent inspection/check execution against exact outputs; retain receipts and return a bounded review packet to the Controller. |
| Prepare / auto-land / promote | Compose and check the actual integration. Exp-to-Quest-branch land is automatic when the lane's authority gates pass; it records the land report on the integration record, moves the exp to `auto_landed`, and posts the report to the main session. Quest-to-master requires the human comprehension packet and explicit authorization, and conditionally updates only the authorized target. Journal partial progress for recovery. |
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
snapshot and the Quest-to-master promotion packet are projections of the same
records, not second sources of truth. For Quest 2 (esc3), recaps
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
Promotion is an explicit Quest-to-master act: candidate build, checks on a Board
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
runners. The concrete human approval entry path for Quest-to-master remains a
pre-promotion design gate; a model-supplied `actor=human` field is not proof
of permission. Because worktrees are cooperative, bypass of the protocol by a
same-user process cannot be prevented; it must be detectable — target-branch
movement without a matching Board journal is an unreconciled-landing incident.

Authority tiers:

- **Worker commits** in its own worktree and branch: automatic, no gate.
- **Exp-to-Quest-branch land:** automatic when the lane's gates pass on the
  exact integration — deterministic checks for micro; checks plus independent
  review for standard and high-blast-radius — the target is unchanged, the
  result kind satisfies prerequisites, and budget remains. The land records
  its IIUC/TL;DR report, sets the exp state to `auto_landed`, and posts the
  report to the main session. Auto-land changes who signs, not what is
  verified.
- **Quest-to-master promotion:** human, via the comprehension packet, bound to
  the exact checked integration commit.
- **Push or publishing:** separately scoped human authorization; neither
  auto-land nor Quest-to-master approval implies it.

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

In: one host, one bp3 monorepo (OCaml codebase/CLI), SQLite, pi/Zellij, worktrees, bounded
Worker briefs, ceremony lanes, one-off taxi lane, 3-10 child multiplexing with
backpressure, durable reports/questions, deterministic waiting, independent
review, gated auto-land to Quest branches, human Quest-to-master promotion,
recovery, self-hosting safeguards, and queryable evidence-backed recaps.
Retain small-scale fan-out/fan-in without building a general scheduler.

Not required for the MVP:

- A Task/Milestone planning hierarchy, universal graph engine, or workflow DSL.
- Four production harness integrations, remote Workers, a web UI, or splitting
  the monorepo into separate control/launcher/worker repositories before an
  extraction trigger fires (see Repository shape).
- Colima/Docker isolation, hostile-Worker security claims, or unrestricted
  external actions. Isolation remains a follow-up, not a dismissed risk.
- Automatic reruns of stale descendants, automatic Quest-to-master promotion,
  automatic push, forecast engines, archive mining, or model-routing
  optimization before end-to-end value exists.
- Driving esc3 before Quest 1 completes. esc3 is Quest 2, a separate
  one-week build-out Quest, not part of Quest 1's proof.

Adoption is settled: bp3 is the way forward, with no predecessor fallback.
That does not exempt it from measurement. Track human attention, ceremony
cost per lane, bypasses, and rework across the Quest 2 week; cut lanes,
gates, or reports that cost attention without buying recovery, evidence, or
outcomes. Evaluate targeted protocol patterns rather than importing an entire
orchestration platform. More parallelism is not itself an acceptance test.

## Quest 1: bp3 loop on itself

Goal: bp3 coordinates one real change to itself, end-to-end, without human
scheduling, and survives the Controller dying mid-flight. This tests the
coordination loop on real, consequential work without confounding it with a
second product's design. It also creates the central self-hosting risk,
handled above: the running bp3 is always the last promoted build, Workers
edit only the next build, and candidates rehearse against a Board copy.

Each core part gets its thinnest working version in this Quest: protocol
(packet and report ops with stable IDs), board (Quest, exp, execution;
idempotent reports), control (launch plus recovery briefing), runtime
(spawn one visible pi Worker with the bridge extension, reconcile it
after Controller death).
Later exps deepen one part at a time; the whole system never grows
uniformly ahead of evidence.

### The toy fixture

`tests/toy-template/` holds a minimal OCaml project — a `hello` command
slot, one test harness, a README. A script materializes it as a scratch git
repo wherever an exp needs one. It is the permanent conformance and dogfood
target: boring, reproducible, and never graduated. Coordinator bugs are
debugged against the toy, never inside real work.

### Exp 1 — One Worker round-trip

Hand-build the genesis kernel (an exception in transport, never described
as bp3 building itself). Exp 1 is staged; each substep is independently
checkable and the exp is not done until all five pass on the toy repo.

- **1.1 Board and ops skeleton.** OCaml CLI plus SQLite with Quest, exp,
  and execution records; create-Quest/exp ops; immutable brief storage;
  the toy template at `tests/toy-template/` with a materialize script.
  Check: create a Quest and exp against a materialized toy repo and read
  them back through `bp3 context`; no Worker exists yet.
- **1.2 Visible Worker spawn.** Runtime creates the worktree and branch,
  opens a Zellij pane running pi with `plugins/harness-pi/bridge` loaded,
  and records the endpoint (pane, session, worktree) on the execution. The
  bridge registers over the local socket and emits session-ready. Check:
  the pane is watchable by the human, the Board endpoint agrees with
  Zellij, and the runtime holds a ready signal — with no pane text read.
- **1.3 Brief delivery and `hello`.** Control writes the brief to the Board
  (add `hello`, its check, scope, limits); the runtime delivers it via the
  bridge (`pi.sendUserMessage`), never keystrokes. The Worker implements
  `hello` and reports a candidate (commit SHA, check output) by running
  `bp3` ops from its shell. Check: `hello` test green on the exp branch,
  candidate recorded against the exact brief revision.
- **1.4 Blocker, steering, takeover.** The check named in the brief
  deliberately does not exist, so the Worker blocks through the Board
  instead of guessing. The human answers via the blocker briefing; the
  answer is recorded (`bp3 steer`) and delivered by the bridge as a
  follow-up. Then the human types directly in the pane: the bridge signals
  `took_over`, the Controller pauses verification until release. Finally
  the identical candidate report is resent. Check: blocker round-trips
  through records only, takeover is detected and released, and the Board
  still shows exactly one result.
- **1.5 Death and recovery.** Kill the Controller mid-run and again with a
  question pending; a fresh Controller's `bp3 context` briefing matches
  reality both times with no user re-explanation. Kill the Worker pane;
  the runtime reconciles the execution as stale from process/bridge facts
  and does not spawn a duplicate. Check: no lost obligations, no duplicate
  Workers or results, endpoint and liveness facts agree across Board,
  runtime, and Zellij.

If the 1.2 bridge spike fails — the extension cannot register, inject, or
report settled-idle honestly — fall back to owned-process RPC Workers for
the remaining substeps and record live view/drive as a harness-exp debt.

### Exp 2 — Auto-land with land report

A fresh reviewer Worker (never the author) reviews the candidate; gates bind
to the exact integration; auto-land sets `auto_landed` and stores the
IIUC/TL;DR land report (demos, tests, code pointers, revert handle). Revert
is a revert commit; the report survives. Three refusal drills are
mandatory: failing check, hand-moved Quest branch (target mismatch), and
reviewer rejection returning as rework on the same exp. Still the toy repo;
one Worker plus one reviewer, sequential.

### Exp 3 — First self-hosted change, promoted by the human

Make `bp3 context` (the recovery briefing) a real command, built by a Worker
in a bp3 worktree against the next build only. Rehearse the candidate
against a Board copy plus a green toy run. The human promotes from a
comprehension packet (concept-ordered diff tour with file pointers, observed
demo, risks, rollback plan); annex on demand. Pull the deliberate rollback
once in-exp. Any change after authorization invalidates the packet
mechanically. Quest completion is recorded with limitations stated;
remaining exps get explicit dispositions.

If bp3 is down during any of this, work directly to unblock, log it as an
incident, and reconcile it into the Board afterward — commitment to bp3
does not mean work stops when the coordinator does.

## Quest 2: esc3 MVP build-out (one week)

A separate Quest, framed fresh once Quest 1 completes. Goal: a usable esc3
— esc2's MVP capabilities with clearer data, plus queryable day/week
recaps — built entirely through bp3 in one week. bp3's loop is already
proven on home turf, so this week tests transfer, not the coordinator's
existence.

Use esc2's implemented MVP as the behavioral reference, not a requirement
to copy its schema or preserve known reporting defects: plan/done capture,
temporal nesting, contexts, tags, declared metrics,
corrections/history/provenance, plan copying, comparison/rollups, and
text/JSON operation surfaces; any staged parity deferral (including MCP) is
explicit, not silently omitted. Add queryable daily/weekly recaps with
concrete records and fixtures (nesting, overlaps, midnight, corrections,
missing-data versus zero, multi-goal accounting where elapsed time must not
multiply). New project/database; leave esc2 data intact. The broader
Python/web/auth/audio Escapement application is not the scope.

- **Toy template as daily dogfood gate.** Before esc3 work each day, and
  after any bp3 change, one toy run end-to-end (spawn, blocker, auto-land,
  revert). A red toy run pauses esc3 work; the failure becomes a bp3
  incident exp. New bp3 capabilities are dogfooded on the toy before esc3
  ever sees them.
- **Scorecard, running all week.** Accepted, reworked, and blocked exps;
  human-active minutes per accepted change; interventions and repeated
  explanations; ceremony cost per lane; Controller restarts and recovery;
  manual bypasses (target zero unreconciled); blockers and their resolution
  path. The week's second output is the prioritized hardening list: keep,
  cut, and fix decisions tied to logged incidents or measurements. A lane
  whose framing and review cost more Controller turns than its Workers
  spend executing is too heavy and gets loosened.
- **Cross-repo checks.** Every Quest names a home repo; its exps work and
  land there. Findings are never fixed inside the wrong repo's exp: an
  esc3-discovered bp3 bug becomes a linked bp3 exp (structural findings
  earn their own bp3 Quest) with provenance to the exposing esc3 Quest/exp
  and incident. Cross-repo prerequisites name exact commits; an esc3 exp
  resumes only when the named bp3 commit exists and checks out. No
  cross-repo atomic land — each repo lands on its own gates and the Board
  links the commits. During the week, no bp3 change promotes unless the
  toy run and a scripted bp3-driven esc3 smoke exp both pass; every esc3
  change arrives through bp3's gates in the esc3 repo. The daily briefing
  reviews new cross-repo bugs, waiting exps, and anything unreconciled.

Success requires both halves: the user runs esc3 for real days and judges
the recap useful, and every esc3 change arrived through bp3 with land
reports, no manual scheduling, and zero unreconciled landings.

## Tests

These are product acceptance checks, not a claim that the whole matrix passes.
At design time no implementation existed. The active Quest and genesis runbook
now distinguish automated/live evidence from human observations still required;
most broader checks below remain future work.

| Check | Acceptance observation |
|---|---|
| Understandable model | From a Quest view, the user can explain why each exp exists, what it needs, what it produced, and the next decision without reading transcripts or raw SQL. |
| Worker round-trip | A real pi Worker in its worktree handshakes, reads the exact brief, reports a blocker/candidate, and safely retries a lost response. Cross-execution mutations are rejected by the protocol. |
| Protocol counterexamples | Duplicate/conflicting operation IDs, stale ownership, dependency cycles, invalid result kinds, and cancellation/completion races have deterministic outcomes. |
| Tokenless waiting | Proposed 30-minute idle run has zero waiting-attributable provider requests; routine events do not start turns; actionable wakes are bounded and coalesced without losing obligations. Account for unrelated harness background traffic; do not assume exactly-once external delivery. |
| Disposable Controller | Restart during work and during a pending question; replacement reconstructs current state and obligations without duplicate launches or repeated explanation from the user. |
| Blocker briefing | A forced blocker reaches the user with IIUC, challenged next steps, and a recommendation; reply is traceable through handling. |
| Lineage and composition | Fan-out/fan-in consumes exact inputs; selection changes, pins and invalid withdrawals do not silently validate incompatible or stale outputs. |
| Review and authorized land | Independent checks bind to the actual integration; exp auto-land fires only when its lane's gates pass, records the IIUC/TL;DR land report (demos, tests, code pointers), and sets `auto_landed`; Quest-to-master refuses absent, mismatched, or stale human authorization and target movement. Crash recovery reconciles Git and Board; branch movement without a journal is detected and frozen, never silently adopted. |
| Limits and restore | Exhaust a configured limit; interrupt the runtime; restore Board plus referenced artifacts in a fresh location without lost or silently resumed obligations. |
| Lanes and one-offs | A micro one-off goes from request to evidence-backed patch with no Quest conversation; a one-line high-blast-radius change is forced into the high lane; deterministic mechanical changes run without a model Worker. Per-lane ceremony cost is recorded. |
| Multiplexing | Run 3, then 5, then 10 concurrent children including reviewers; review saturation stops new launches; a common blocker consolidates into one question; overlapping scopes warn before launch; resource namespaces keep parallel test runs apart; a snapshot after Controller restart reconstructs the full roster. |
| Land report and promotion packet | Every auto-land produces exactly one stored report — TL;DR, IIUC, demos, tests, code pointers, revert handle — posts it to the main session, and sets `auto_landed`; silence is never treated as consent; a revert restores a non-landed disposition without erasing the report. The Quest-to-master packet explains the integrated diff by concept, binds receipts to the exact commit, and is invalidated by any later change; an oversized Quest is split before the gate. |
| Self-hosting | A Worker exp that would corrupt the Board, launcher, or land path is caught on a Board copy; the running build is unaffected; promotion switches atomically and rollback restores the prior build. |
| Useful dogfood | Quest 1: bp3 lands and promotes a change to itself through exps 1-3 without manual scheduling. Quest 2: esc3 is built entirely through bp3 in one week behind the daily toy gate, with the scorecard, hardening list, and cross-repo checks all exercised. |

Measure human active time, interventions/repeated explanations, accepted
outcomes, useful learning, elapsed time, ceremony cost per lane, and total
model/check/rework cost. Unavailable measurements remain explicit. A low
token bill with more human babysitting is not success; because adoption is
settled, report these as friction to fix, not as an adoption verdict.

## Proposed delivery milestones

These are the original design-stage experiment proposals, **not a new
Milestone entity**. Current Board records and progress are tracked in the active
Quest; do not infer completion from this proposal table.

| Exp | Shippable output and decisive check | Depends on |
|---|---|---|
| Q1E1 — One Worker round-trip | Staged 1.1-1.5: Board/ops skeleton, visible bridge Worker spawn, brief + `hello`, blocker/steer/takeover with duplicate-report safety, death and recovery. Each substep independently checkable. | None |
| Q1E2 — Auto-land with land report | Fresh reviewer, gated auto-land to `auto_landed` with stored land report, revert commit, and all three refusal drills (failing check, moved target, reviewer rejection) on the toy repo. | Q1E1 |
| Q1E3 — Self-hosted promotion | `bp3 context` built by a Worker, rehearsed on a Board copy plus green toy run, human promotion from a comprehension packet, deliberate rollback. Quest 1 completes. | Q1E2 |
| Q2 — esc3 MVP build-out week | Separate Quest: esc3 built entirely through bp3 in one week, toy template as daily gate, scorecard running, cross-repo checks active. | Quest 1 complete |

Named future exps, deliberately undated — each is specced from what the
Quests teach, not designed in advance: protocol counterexample fixtures
(retries, ownership, races) grown from Q1E1's live cases; tokenless waiting
and the 3-to-10 multiplexing ramp under backpressure; evolving lineage
(fan-out/fan-in, pins, withdrawals); lanes and one-off hardening from
measured ceremony cost; the Muse harness adapter under the
ControllerAdapter conformance suite (owned `muse serve` or ephemeral
`muse exec`; never foreign-TUI typing); isolation. Other harnesses and
isolation never block proof of the cooperative pi workflow.

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
3. **Review, land, and promotion — owner: designer; human owns Quest-to-master.**
   Define the auto-land gates, land report, and `auto_landed` state; how
   deliberate human promotion is recorded, its exact action scope, the
   comprehension packet and Quest-size
   budget, verifier authority, integration target policy, the recovery
   journal, and self-hosting promotion/rollback. Recommend an explicitly named
   Quest integration branch; promotion and external push are separately scoped
   actions. This gates E5, not a promise that worktrees enforce authorization
   against a hostile process.
4. **Queries and recaps — owner: designer with user evaluation.** Pin day/week
   windows, current-corrected versus historical semantics, traceability, the
   Quest 2 scorecard fields, and the smallest useful output fixtures. Keep
   bp3 coordination projections and the later esc3 activity projections
   separate; both must be queryable, not only prose.

The next design pass should produce small worked records and failure traces
before detailed SQL, a full command catalog, or any repo split.

## Red chair record

- **User input:** strongest attack was optimizing "fewer edges" rather than
  understandability. The user clarified the requirement; the MVP now centers
  clear Quests/exps and separates that requirement from esc3's storage choice.
- **Problem space:** another Escapement rewrite or more parallel Workers could
  ship without reducing friction. The user settled this: bp3 builds bp3 first,
  esc3 is Quest 2, and adoption is not on trial. Measure human
  attention, ceremony per lane, and bypasses during Quest 2 and cut
  whatever does not buy recovery, evidence, or outcomes.
- **Solution:** a CLI/worktree is not a security boundary, and a notification
  is not durable delivery. Carry forward tiered authority (gated auto-land to
  Quest branches, human comprehension-gated Quest-to-master, separately scoped
  push), atomic events, idempotency, ownership, independent receipts, exact
  integration binding, and unreconciled-movement detection. The unresolved
  concrete mechanisms are gates in design slices 1–3, not implemented
  guarantees.
- **Milestones:** "use bp3 to build bp3" hides a bootstrap dependency and a
  self-corruption risk; building four adapters or all of Escapement hides the
  riskiest useful slice. Make the hand-built genesis kernel and the
  stable-host/promotion split explicit, prove one real round-trip and
  idle/restart behavior, multiplex 3-10 children under backpressure, then run
  Quest 2's esc3 build-out week behind the daily toy gate.

## Handoff

This document alone authorizes no launch, merge, push, or external action.
The user's implementation request activated the MVP Quest. The governing
[genesis exp record](../exp/2026-11-05-genesis.md) resolves the Exp 1
subset of design slices 1–2; the broader proposals here remain historical
inputs/future work, not a competing implemented contract. Exp 2/3 still need
their review/integration/promotion packets. Changes to agreed intent/scope and
Quest-to-master promotion remain explicit human decisions.
