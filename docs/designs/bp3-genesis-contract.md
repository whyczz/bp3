# Genesis implementation contract (MVP Exp 1)

This packet resolves the Exp 1 implementation decisions in
[bp3-control-mvp.md](bp3-control-mvp.md). It does not authorize promotion or
push. Genesis is direct-authored bootstrap, not self-hosting.

## Boundary

OCaml owns protocol, SQLite operations, CLI, worktree launch and the local
runtime. One small TypeScript pi extension adapts documented lifecycle hooks.
Only the standard/code lane and one live author execution are admitted here.
Independent review/integration/promotion are Exp 2/3, not placeholder approvals.
Unsupported prerequisites and other lanes are rejected rather than ignored.
The initial `context` is a JSON recovery snapshot; the human-oriented briefing
remains the Worker-built Exp 3 change.

## Records and transitions

- Quest: intent, canonical home repo, named integration ref, exact base commit.
- Exp: immutable structured brief (objective, acceptance, scope, non-goals,
  check argv, wall-clock limit), Quest and exact base. Amendments/replacement
  are not silently implemented by mutating a brief.
- Execution: exp, generation, frozen brief/base, branch/worktree, random token,
  launch stage, pi session/pane/PID, desired state and independent observations
  (ready, busy/settled, permission, takeover, last heartbeat).
- Result: one immutable code candidate per execution, exact commit and Worker
  evidence. This is a claim, never an independent check or approval.
- Question: IIUC, challenged next step, recommendation, reply and handling.
- Inbox: durable message, optional question link, delivery stage.
- Event + receipt: every successful mutation and its event commit atomically.

Exp transitions: `working -> blocked -> working -> ready`; cancellation is
explicit and preserves questions and evidence. A lost bridge is `stale` on the
execution, not a fabricated success/failure of the exp. No automatic respawn.
A takeover is an orthogonal latch: automated delivery and candidate submission
pause until explicit release. A release does not pretend the pi agent is idle.
A reported candidate never grants land/promotion authority.

## Retry and fencing

Mutations use protocol v1, globally stable operation ID, operation and payload.
Worker/bridge requests also carry execution ID, generation and token. IDs are
restricted ASCII slugs; tokens are random local capabilities, not a hostile-code
security boundary. Credential validation precedes receipt lookup. Worker receipt
replay precedes terminal/generation checks: an already committed report remains
acknowledgeable after cancellation, but no new obsolete mutation is permitted.
Bridge receipts are different: an inbox offer can start work, so replay must
revalidate live authority, session identity, and (for offers) takeover/permission
and readiness. A withdrawn offer fails closed; it cannot resurrect authority.
Reusing an operation ID with different content fails. Concurrent calls serialize in a
short SQLite `BEGIN IMMEDIATE` transaction with foreign keys and busy timeout.
No transaction encloses Git, process launch, or a model call.

## Runtime and launch

One runtime per Board holds an OS file lock and serves a mode-0600 Unix socket.
The Controller's CLI is disposable. The runtime neither invokes a model to
wait nor reads pane contents. Zellij is only a terminal host. A launch reserves
an execution before side effects, then journals worktree creation and spawn
intent. A repeat launch returns the reserved execution; it never repeats an
ambiguous spawn. The bridge supplies the real pane ID, PID and pi session;
ready is recorded before any brief may be dispatched. Incomplete launch stages
remain visible for explicit recovery, not silently retried. Capabilities are
passed through a mode-0600 launch file, not Zellij's inspectable pane argv.
The bootstrap binary and bridge are frozen per live fixture, not run from a
changing build directory; this is not yet the Exp 3 promotion mechanism.

The bridge exchanges signals and durable inbox messages over the socket.
Heartbeat polling is deterministic (no provider calls). `agent_settled` plus
`isIdle()` is the only final-idle signal; `agent_end` is not used. Interactive
`input` and user shell actions latch takeover. Permission dialogs are signals.
A ready Worker holds until the Controller explicitly queues its brief.

Delivery stages are `queued -> offered -> observed -> handled`. An offered
message is never blindly re-offered under a new request: delivery across a
process crash is ambiguous, not exactly-once. Lost socket responses retry the
same operation ID and replay the same offer only while authority is still valid.
Local takeover/permission latches guard the gap before their Board signals.
An offer racing a latch can remain ambiguous; there is no automatic reinjection
or in-place recovery command in genesis. A protocol fence stops delivery and
requests a pi abort, whereas transport loss retains the same pending request.
`input` proves observation;
only explicit Worker `answer-handled` proves a question handled. Settled-idle
alone does not resolve questions. Stale/ambiguous deliveries appear in context.
Reload/session replacement is fenced by the original pi session identity.
Runtime restart accepts heartbeats from the same living Worker; it does not
spawn. Expired execution wall-clock budgets fence new work without killing an
unrelated process or guessing PID ownership. Cost is unknown, not zero.

## Acceptance and stopping point

`dune runtest` exercises Board transitions, concurrency/retry counterexamples,
and process/runtime recovery without provider calls. The toy template is a
separate materialized Git repo; it starts with a deliberately failing `hello`
check. Live pi/Zellij runs supply separate receipts, never conflated with mocks.
Human-only gates are watchability, a real blocker answer, direct pane takeover
and release. Exp 1 is not complete until these observations are recorded.
All five Exp 1 stages have now been observed, including human input and real
Controller process replacement (see the linked runbook). Exp 2's next boundary
is described in [the proposed auto-land packet](bp3-auto-land-contract.md);
it does not retroactively turn genesis reports into review/land approvals.

SQLite backups use its online backup API into a new file. A Board snapshot is
not a complete portable backup of the referenced Git repositories/sessions;
that limitation remains explicit until restore rehearsal is implemented.

The launcher currently performs synchronous Git/Zellij calls. A hung external
command can delay heartbeats and reconciliation; command deadlines and async
launch supervision remain hardening work. Cancellation/budget exhaustion fences
protocol work, but is not an OS sandbox or a guaranteed process-tree kill.
Heartbeat receipts/events grow without compaction. No paid-cost accounting or
30-minute tokenless-waiting proof is claimed by this implementation.

See [genesis runbook and evidence](../genesis.md) for the actual acceptance
observations, review findings, and outstanding human gates.
