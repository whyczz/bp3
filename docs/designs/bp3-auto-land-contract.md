# Auto-land implementation contract (MVP Exp 2)

Status: proposed implementation packet; not an implemented guarantee.
Governing scope: [MVP Quest, Exp 2](../quests/2026-11-05-bp3-mvp.md).
Genesis evidence: [runbook](../genesis.md). No master promotion or push authority.

## TL;DR

A fresh reviewer and an independent check must approve the exact commit that
moves the Quest branch. For Exp 2, integration is **fast-forward only**, from the
frozen base: do not introduce merges, cherry-picks, or automatic rebases. Journal
intent before the compare-and-swap ref update; recover the Board afterward.
Rejected reviews create rework on the same exp, never overwrite old evidence.

## ELI5

The author submits a sealed parcel. Someone else inspects it; a separate test
run checks it. Only that parcel can go onto the Quest shelf, and only if nobody
has moved the shelf since we checked. A receipt says exactly what landed and
how to undo it. Master is a different shelf, still requiring the human's approval.

## Context and bootstrap boundary

Current `Workflow.report` stores a candidate, not approval. `Authority.allowed`
has Controller/Worker/Bridge/Runtime permissions but no verifier/reviewer role.
`Execution_ops.reserve` permits only generation zero, and `Store.schema` has one
live-author slot. `Launcher.launch` refuses unrecorded target movement. These
are intentional genesis limits, not APIs to bypass with direct SQL or Git.

The user authorized two source checkpoints: the standalone skill fix on
`master` (pushed), then Exp 1 on `quest/bp3-mvp` (local only). The Quest checkpoint
includes the skill-fix parent, but its own diff isolates the genesis kernel and
handoff. This is a bootstrap exception, not auto-land or master promotion. Keep the old bootstrap Board as historical
provenance; explicitly establish the new implementation Board at that exact
checkpoint. Do not silently rewrite an existing Board's frozen base to match
a hand-moved branch. Record the checkpoint hash and the source-file disposition.
Use the resulting exact Quest commit as the implementation Worker's baseline;
checkpoint authorization is not authorization to push or promote Exp 1.

Exp 2 kernel work is delegated through the existing genesis runtime to a Worker
on that committed baseline. That runtime stays frozen; the candidate kernel
is tested on Board copies and fresh toy repos. Do not hot-swap the coordinator
executing the implementation exp. The toy auto-land proof is separate from
accepting/activating the kernel that implements it.

## Architecture and data

```text
frozen author brief -> author execution -> immutable candidate
                                           |
                           independent verifier + fresh reviewer
                                           |
                            exact gates + journal reservation
                                           |
                            Git compare-and-swap Quest ref
                                           |
                         durable land report / recoverable journal
```

The existing standard/code-only, single-host, cooperative trust model remains.
One author and one reviewer maximum, sequential is sufficient. No general DAG,
lanes, external push, master promotion, production sandbox, or autonomous rebase.

Required additions (names may be refined in the Worker design, invariants may not):

- **Execution role** `author` or `reviewer`, from Runtime reservation, not a
  caller-controlled report field. A reviewer binds to one exact candidate and
  must have a different pi session/execution/worktree from the author.
- **Execution terminal state:** reporting seals an author candidate and ends its
  author lease without discarding evidence. Review completion similarly ends
  the reviewer lease. A late heartbeat must not restart a sealed execution.
- **Verification receipt:** candidate ID, exact commit/base, frozen check argv,
  independent workspace identity, exit status, retained stdout/stderr, clean
  tree observation and time. Worker prose is never a verification receipt.
- **Review receipt:** candidate ID + exact commit/base, reviewer execution,
  accept/reject, findings and evidence. The author credential cannot write it.
- **Integration intent:** stable operation/intent ID, exp, selected candidate,
  exact before/after ref, target ref, bound verifier/reviewer receipts, and
  progress (`prepared`, `applied`, `finalized`, or `incident`).
- **Land report:** exactly one per successful integration, TL;DR, IIUC, demos,
  tests, code pointers and revert handle. Retained after rework or revert.
- **Rework:** selected candidate/review disposition and explicit reason retained;
  same exp, new author ownership generation/execution, old evidence immutable.
  A rejected or obsolete candidate cannot become selected via receipt replay.
- **Incident:** actual/expected target, intent if any, reason and blocked state.
  Target movement without a matching intent freezes integration, never becomes
  the new base just because a retry saw it.

Author ownership generation and reviewer identity must not fight over the
current `UNIQUE(exp_id,generation)` constraint. Specify the migration and
per-role/current-selection constraints before adding another launcher shape.
Do not increment the author's generation merely to start its reviewer.

## Operations and authority

1. **Prepare/verify candidate.** Read the sealed result and immutable brief,
   ensure target equals its frozen base, and create an independent worktree at
   the exact candidate. Run check argv directly (no shell interpolation),
   outside SQLite transactions, with a bounded deadline. Capture output outside
   the candidate. Require the committed/tracked tree and HEAD to remain exact;
   reject tracked or untracked source changes. Build artifacts may be ignored.
   Persist success or failure honestly. No receipt on interrupted execution.
2. **Start reviewer.** Runtime reserves a reviewer tied to that candidate and
   launches a fresh pi session/worktree. Give it the frozen brief, exact diff,
   and verifier evidence; require findings and accept/reject through Board ops.
   No author-role token can manufacture review approval.
3. **Rework.** Reviewer rejection returns the exp to rework/working on the same
   identity. A new author execution consumes the rejected candidate/findings;
   generation fences its predecessor. Scope/check changes need explicit recorded
   amendments, not reinterpretation of free-text steering. Exp 2's happy-path
   fixture uses an existing concrete `dune runtest --root .` check; do not parse
   the Exp 1 human answer's prose into an executable gate.
4. **Auto-land.** Deterministic runtime action after both gates, not an author
   command or another human scheduling step. Revalidate selected generation,
   candidate/base/check/reviewer bindings, budget/cancel/takeover/permission,
   absence of unresolved questions, and target identity. Record an exclusive
   integration intent before touching Git. Never land to master or a non-Quest
   ref. Refuse a target checked out in any worktree, rather than silently
   invalidating that worktree's index.
5. **Apply/reconcile.** `git update-ref TARGET AFTER BEFORE` is the only target
   mutation for land. Transactionally finalize the exp as `auto_landed`, update
   the recorded Quest head, and insert exactly one land report/event/receipt.
   No SQLite transaction spans a process call. Restart with a prepared intent:
   if actual ref is BEFORE, recheck gates and retry the CAS; if AFTER, finish the
   recorded action once; if neither, freeze as an incident. An AFTER ref without
   a matching durable intent is not evidence of authorized landing.
6. **Revert.** Controller may explicitly request a revert of an auto-land on
   the Quest branch. Create a **new revert commit**, not a reset or history
   rewrite, in an owned worktree; journal and CAS against the exact current
   head. Reject conflicts/moved targets rather than choosing resolutions. Mark
   reverted disposition and retain the original land report plus the revert
   receipt. The fixture deliberately returns to its failing baseline; a revert
   is recorded as an undo, not a newly accepted feature with invented green
   checks. Master rollback/build activation remains Exp 3.

A live Controller dying does not make it the owner of a new execution. A fresh
Controller reads existing obligations and lets the runtime resume only the
journaled action. The same stable operation ID replays the same result; reuse
with changed input is a conflict. Report receipts and execution authority remain
separate, including bridge cached-offer fencing from genesis.

## Storage, migration, and compatibility

Schema v1 is explicitly checked in `Store.open_db`. Add a named v1-to-v2
migration, never silently migrate while an old runtime is attached. Acquire
exclusive runtime ownership and take a consistent backup first. Preserve all
old rows, frozen briefs, receipts, event cursors, and terminal obligations.
Retain schema v1 Boards as genesis evidence. Test migration on copies; the
running genesis runtime continues using its original v1 Board/binary/bridge.
Older binaries must fail closed on the new schema, not interpret new states.

The integration journal bridges SQLite and Git; a SQLite backup alone is still
not a portable artifact backup. No claim of full restore until rehearsed.
Independent worktrees are evidence isolation from accidental author changes,
not a hostile-code security boundary.

## Acceptance checks

All currently fail by absence of implementation; none are claimed passed.

- Fresh author/reviewer identities; author cannot approve itself or supply a
  successful verification receipt. Review binds to the exact candidate.
- Independent check failure produces no target movement, no land report and no
  `auto_landed`, even when Worker evidence says the check passed.
- Hand-moved target creates an incident and remains untouched; do not silently
  rebase the brief or auto-retry against the new head.
- Reviewer rejection yields rework on the **same exp**, with a fresh author
  generation; obsolete reports/reviews cannot resurrect the rejected result.
- Happy path on a fresh toy repo: exact independently checked/reviewed candidate
  auto-lands once, emits the compact stored report, and names a working revert
  handle. No master movement, push or extra scheduling approval.
- Duplicate/concurrent land requests and runtime death before/after ref CAS
  yield exactly one landing/report or a visible incident, never guessed success.
- Cancellation/takeover/budget/permission, unresolved question, changed
  verification workspace, mismatched receipt and checked-out target all refuse.
- Revert produces a new commit, restores the baseline tree, keeps both receipts,
  and refuses target movement or integration conflicts.
- Schema migration preserves a copy of the populated Exp 1 Board; old running
  binaries/fixtures remain unchanged throughout candidate testing.

## Delivery slices within Exp 2

1. Roles, terminal/rework transitions and schema migration with counterexample
   tests — start from this authorized source checkpoint with a fresh Board,
   not the historical pre-genesis Board.
2. Independent verifier and fresh reviewer with reject/rework proof.
3. Journaled auto-land, report, crash/refusal drills and explicit revert.
4. Live toy rehearsal + read-only adversarial review of the result. Only then
   begin Exp 3's promotion/activation design and Worker-built context briefing.

## Red-chair record and open decisions

- **Input:** the user observed a finished Worker, not an approved/landed result.
  Keep the verified candidate and Exp 1 completion separate from Exp 2 claims.
- **Problem:** a happy-path merge command would not establish independent
  approval or survive the Git/SQLite boundary. Existing Board authority and
  one-generation constraints must change explicitly, not via test-only SQL.
- **Solution:** merging after reviewing the author SHA could land a different
  tree. The cheapest sound boundary is exact fast-forward integration with
  independently checked/reviewed candidate SHA and expected target CAS. A
  future need for composition would require a new exact-integration contract.
- **Milestones:** immediately spawning a Worker from current HEAD would omit
  all genesis code; committing the entire dirty tree would absorb unrelated
  installer work. Isolate the source checkpoint before delegation. Manual
  checkpoint permission is bootstrap friction, not a recurring product gate.

Owners: implementer resolves concrete schema/API names and bounded process
supervision; Controller reviews their invariants before build. Human owns the
authorized source-checkpoint split and eventual Quest-to-master comprehension
approval, not ordinary Exp 2 scheduling. Cost accounting and UI notification
presentation remain explicit limitations; the stored report must still exist.
