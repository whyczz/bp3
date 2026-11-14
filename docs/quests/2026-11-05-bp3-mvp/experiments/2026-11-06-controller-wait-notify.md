---
date: 2026-11-06
quest: ../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — Zero-token waiting and a responsive Controller

## TL;DR

Let the runtime wait and a thin Pi extension notify. Keep the Controller free
for human conversation instead of spending model turns asking whether Workers
have finished. Routine events update the UI; only decisions warrant model work.

Status: **proposed follow-up, not implemented or verified**. The human approved
deferring this work, not launching it. It is outside the original MVP acceptance
gates. Default ordering is after Exp 3; earlier scheduling requires explicit
reprioritization. No Board, Worker, promotion or push is authorized by this record.

**Temporary operational allowance — 2026-11-06:** the human permits bounded
Controller polling/looping **for the current iteration only** to drive progress.
This does not implement this exp, change its zero-provider-request acceptance,
authorize provider-refusal workarounds or reset any work budget. It is an explicit
short-term practice, not a permanent architecture decision.

## Context and scope

The home source checkpoint is `e442374f9866b639078ed9f688c1f752d45a35df`;
[Exp 2](2026-11-05-auto-land.md) has a separate, unaccepted kernel candidate.
The runtime already reconciles on ordinary-code timers, and the Worker bridge
already heartbeats without model polling. Neither establishes a complete
Controller subscription, durable notification or zero-provider-request proof.
Manual Controller polling during the Exp 2 review exposed that missing path.

In: a Board-bound event follower, durable delivery progress, cheap Controller
status/notifications, bounded decision wakes, reconnect and human-priority behavior.
Out: a second coordinator, terminal scraping, whole-workflow scheduling, increased
Worker concurrency, background model polling or a general plugin framework.
[Exp 5](2026-11-06-bounded-workflow-loop.md) owns routine workflow automation.

## Mini-design and code tour

```text
Workers -> Board facts/events -> runtime event follower
                                      |
                           Controller Pi extension
                             |                 |
                       status / notify    decision pending
                         no model        bounded model wake
```

- **Durable truth:** Board operations retain obligations and delivery progress.
  A cursor is scoped to the Board and Controller binding; an event is a hint to
  read current state, not authority to replay an obsolete action. Notification
  receipt must not mark a question answered or handled.
- **Waiting:** the runtime follows a public, capability-filtered projection.
  Bounded cursor polling is acceptable; SQLite file-watch callbacks alone are
  not a reliable queue. Coalesce routine heartbeats without dropping blockers.
- **UI:** the extension displays status and notifications without injecting a
  model message. Human notification, model wake and workflow scheduling are
  different operations. Pi's in-process extension event bus is not a durable
  cross-process Worker transport.
- **Decision delivery:** persist pending work before attempting a wake. Prefer
  human input while the Controller is busy; retain/coalesce background decisions
  for a safe boundary rather than repeatedly steering the conversation. Re-read
  Board authority before acting. An ambiguous wake after a crash stays visible;
  do not promise exactly-once external model invocation.
- **Ownership:** one bound subscriber may request decision wakes. A stale or
  conflicting Controller cannot gain effect authority through notification replay.
  Closing Pi must not stop runtime reconciliation. Keep the Controller tab
  separate and Workers visible in the same bound Zellij session.

Existing responsibility anchors, not claims of a completed Controller extension:
[`Runtime.serve`](../../../core/runtime/runtime.ml) owns singleton reconciliation;
[`Store.snapshot_json`](../../../core/board/store.ml) exposes a consistent cursor;
[`Board.apply`](../../../core/board/board.ml) owns authenticated operations;
[the Worker bridge](../../../plugins/harness-pi/bridge.ts) demonstrates transport
and UI hooks, not a second policy engine. Read the installed Pi extension docs
and examples in full before implementation and test actual dispatch semantics.

## Acceptance and evidence

All checks below are **not run** for this exp.

1. Observe an otherwise idle Controller for 30 minutes with routine Worker
   signals: **zero waiting-attributable provider requests**, including cache
   warming, and no growing model transcript of progress polls. Record the
   request-observation method and unrelated traffic separately; unknown cost
   is not zero cost. Disable warming for the strict test and state the possible
   next-wake cache-miss tradeoff.
2. One actionable batch produces one coalesced bounded decision turn in normal
   operation. Duplicate events do not schedule duplicate effects; heartbeats
   and successful status updates start no model turn.
3. Kill/restart the follower and Controller around cursor/wake boundaries.
   Pending obligations survive, the replacement catches up, and ambiguous
   dispatch is inspectable without claiming exactly-once inference.
4. While a Worker runs, the human can converse, inspect state, pause automation
   and request another eligible Run without a Controller wait loop or stolen
   focus. Busy delivery preserves the human message and pending decisions.
5. Cancellation, expiry, takeover, changed generations, a foreign Board and a
   conflicting subscriber cannot turn stale events into authorized work. The
   existing one-author/one-reviewer capacity remains enforced.

## Runbook, recovery and human touchpoints

Freeze an exact implementation source and test on a fresh fixture/Board copy.
First use a counted fake provider for deterministic delivery tests; an approved
live idle drill must separately measure actual provider requests and human
responsiveness. Do not spend paid turns merely to monitor that drill.

A documented disable/pause operation must stop automatic wakes without deleting
Board obligations or stopping runtime-owned cleanup. Reconnect from durable
progress and current state, not a transcript. Human input owns reprioritization;
notification silence never authorizes promotion or push.

## Red chair and next step

Strongest attack: a notification extension becomes a second coordinator or a
paid event storm. Keep scheduling/effects in core, expose only filtered facts,
and make no-inference waiting plus human responsiveness decisive acceptance
checks. Start with one Controller and the existing capacity, not multiplexing.
Before delegation, pin the subscriber ownership, delivery/acknowledgement and
ambiguous-wake recovery contracts against the installed Pi API.
