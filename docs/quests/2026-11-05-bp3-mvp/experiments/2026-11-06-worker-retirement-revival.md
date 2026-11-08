---
date: 2026-11-06
quest: ../QUEST.md
exp: 8
status: proposed
---

# Exp 8 — Automatic Worker tab retirement and explicit revival

## TL;DR

Finished Workers should not leave a graveyard of unused tabs. Safely retire their
owned terminals without deleting their work or context. When needed again, the
Controller can explicitly revive useful context under a new assignment/Run.

Status: **proposed follow-up, not started**. Requested on 2026-11-06 after the
human asked to close `exp2-astra-author`. No change to Exp 2's current cleanup
triggers, the active Exp 7.1 brief, or the original MVP completion gates.

## Context, dependencies and scope

Exp 2 implements [post-land retirement](2026-11-05-auto-land.md#post-land-worker-retirement-and-human-release),
not generic collection of submitted, cancelled or expired Workers. Its current
contract explicitly keeps reported/awaiting-review Workers open. Closing those
automatically is a **new policy**, not permission to reinterpret existing gates.
[Exp 7](2026-11-06-reusable-workers-reviewers.md) supplies context forks; a reusable
context does not require keeping the original Pi process/tab alive.

Depends on accepted Exp 2 cleanup safety and Exp 7's verified fork primitive.
Default scheduling is after Exp 3 unless explicitly reprioritized. Exps 4/5 may
later expose notifications or automate scheduling, but are not needed for the
bounded terminal-lifecycle policy itself.

In: automatic closure of eligible completed-unused terminals, reconciliation of
known exited owned terminals, preserved evidence/context and explicit revival.
Out: inactivity-based killing of busy work, full process-tree supervision,
unbounded automatic retries/respawn, stronger isolation, new concurrency or
silent budget renewal. General handling of abandoned work still needs an explicit
disposition; a stale heartbeat is not proof of a dead process or completed exp.

## Mini-design and responsibility map

```text
immutable submission + settled + no obligations/interaction
                          |
             retain/pin history and context
                          |
               durable retirement request
                          |
             runtime closes exact owned terminal
                          |
             history remains inspectable
                          |
          explicit Controller request to work again
                          |
            NEW Run + budget + workspace + fork
```

### Retire a terminal, not the evidence or the exp

- Separate **work authority**, **code acceptance**, **process/terminal presence**
  and **context availability**. Closing an awaiting-review author is neither
  acceptance nor cancellation of its candidate. Removing a dead terminal cannot
  fabricate a successful retirement, land or handled blocker.
- Make eligibility policy explicit: completed immutable submission, current
  settled state, no pending inbox/permission/question/editor input/takeover and
  retained usable context. A short configured grace period may aid inspection;
  expiry of that timer never overrides safety holds.
- Runtime owns durable requests and bounded graceful shutdown. Reuse session/
  process-incarnation/pane/interaction-revision guards and final local input
  checks. Exact already-exited terminals can be reconciled without killing a
  guessed PID. Keep ambiguous ownership or surviving processes visible as holds.
- Add a distinct completed-unused retirement reason; do not fake a land report
  to feed the existing post-land queue. Historical records and artifact references
  remain readable after closure. Do not remove worktrees, branches, review/repro
  evidence, session files or the source needed for a context fork.
- Human interaction wins a close race. Retain an explicit keep-open/takeover
  hold and use the existing release semantics where applicable; ordinary idle
  completion must not require another human command. Never close the Controller,
  shared session/window or a tab containing unrelated terminals.

### Revival means new authority

- An explicit Controller request identifies retained source context and the
  intended new work. Distinguish opening evidence for inspection (no model work)
  from authorizing another task. A label such as “revive Worker” must explain
  which of those actions it will perform.
- To work, use Exp 7's pinned fork into a new Run/session/worktree, with a new
  bounded budget and explicit brief/current inputs. Preserve the old Run's
  expired/sealed/retired disposition; old credentials and queued messages never
  become current authority. Do not reopen the old session in its old workspace.
- Same-scope rework remains another Run on the same exp; a new objective requires
  a new exp. If the target/base has advanced, require an explicitly refreshed
  assignment and checks, not a silent rebase or rewritten frozen base.
- Deduplicate revival requests. Ambiguous partial launch yields a visible hold,
  not repeated forks. No automatic loop that closes a Worker and immediately
  respawns it. Existing capacity/backpressure and independent-review rules remain.
- A revived reviewer-context fixer is an author for its fix. Its next independent
  reviewer starts without author/fixer conversation ancestry.

Existing responsibility anchors are [runtime ownership](../../../core/runtime/runtime.ml),
[launch reservation](../../../core/runtime/launcher.ml),
[Run observations](../../../core/board/run_ops.ml) and
[bridge interaction](../../../plugins/harness-pi/bridge.ts). These home paths are
still the frozen-v2 baseline; Exp 2's unaccepted candidate adds cleanup machinery.
Do not claim the new retirement policy or revival command exists today.

## Acceptance and evidence

All new behavioral checks below are **unrun**.

1. A submitted, settled author awaiting review retires automatically under the
   new explicit policy, without a fabricated land/cancel. Its exact Outputs,
   worktree, session and check/review references remain inspectable. The same
   holds for an eligible completed reviewer with all obligations resolved.
2. Takeover, unfinished typing, pending messages, permission prompts, questions,
   active work and newly arriving interaction prevent unsafe closure. Stale
   heartbeats/expired budgets alone cannot trigger force-kill or lose work.
3. Restart around retention, graceful shutdown and terminal removal converges
   without duplicate actions, lost context or wrong-target closure. Reused PID/
   pane IDs, renamed/shared tabs and foreign sessions refuse unsafe cleanup.
4. A known exited owned terminal is removed without touching other panes or
   inferring its exp succeeded. Public context distinguishes last observation,
   current terminal state and work authority instead of leaving a false live claim.
5. Explicit revival creates one fresh authorized Run in a mounted tab with pinned
   context, current cwd/input/model and old history untouched. Duplicate requests
   do not spawn twice; missing/changed context or stale base stays inspectable.
6. Old credentials cannot report/steer the new Run, a retired source cannot gain
   work authority through a heartbeat, and fixer-context lineage cannot authorize
   independent review. No automatic budget refill or capacity bypass.

## Triggering observation — not acceptance

The human explicitly requested closure of the old `exp2-astra-author` tab after
its exact candidate `e512fe5` was submitted and its work lease expired. The
Controller verified its stored idle/no-takeover/no-permission state, no queued/
offered inbox or open question, clean candidate worktree, exact process cwd/birth
and one owned terminal. It closed only `terminal_4` in tab `1` of the bound session.

Fresh metadata confirms that terminal/tab and recorded Pi PID are gone; the
Controller, prior reviewer and active Exp 7 author tabs remain. Candidate,
worktree and session file are retained; the session SHA-256 is unchanged.
Receipts: `.bp3/exp2/exp2-astra-author-{manual-close,closed}.json`.
This was explicit human-requested cleanup, not automatic retirement or Exp 2
acceptance. Frozen v2 still projects the expired Run's last `observed=live` value;
no raw SQL or fake lifecycle signal repaired it. That limitation motivates a
proper runtime-owned closure/projection path, not a claim it already works.

## Red chair, runbook and next step

Strongest attack: an “unused tab” heuristic closes someone typing, deletes the
only retained context, or revives stale authority. Require positive completion/
settling evidence, interaction-safe shutdown, pinned retained context and new
assignment authority. If those facts are ambiguous, hold rather than guess.

Test on disposable Boards and sessions with frozen builds. Exercise crash/race
cases before an authorized visible rehearsal. Keep provider-free revival tests
separate from paid task execution. Disabling automatic retirement must stop new
close requests without reviving already-closed work or erasing pending obligations.

Next: after prerequisites are accepted, pin the smallest eligibility/grace/hold
and inspection-versus-work interfaces. No Worker is launched for this proposal,
and no current policy or active assignment is amended by writing it down.
