---
date: 2026-11-06
quest: ../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Bounded author, review and rework automation

## TL;DR

Automate routine next actions without making the Controller babysit each handoff.
The reviewer supplies findings and repros; the Controller checks the packet and
records a disposition plus optional human feedback. A new author Run fixes the
accepted findings, preferably using that reviewer's context through
[Exp 7's fork handoff](2026-11-06-reusable-workers-reviewers.md). A genuinely fresh
reviewer judges the new exact outputs. A deterministic, bounded policy drives
existing operations and escalates decisions instead of inventing new authority.

Status: **proposed follow-up, not implemented or verified**. Default ordering is
after [Exp 4](2026-11-06-controller-wait-notify.md), using the accepted Exp 2
kernel. This backlog record does not start work or expand MVP completion gates.

## Context and scope

The implementation starting point remains to be frozen at delegation. Home
checkpoint `e442374f9866b639078ed9f688c1f752d45a35df` is the genesis coordinator;
Exp 2's separately submitted v3 candidate is not activated. Its
[existing rework contract](2026-11-05-auto-land.md#atomic-rework-reservation)
already requires sealed Outputs, atomic replacement reservation, immutable
findings and fresh exact-commit review. This exp automates routine orchestration
of that contract; it does not defer its correctness or acceptance into the future.

In: durable next-action policy, bounded rework attempts, repro handoff, pause,
recovery and escalation. Out: new lifecycle layers, a workflow DSL, parallel
authors, increased capacity, automatic scope/base changes, lease resurrection,
master promotion or push. No second unfenced Controller is introduced.

## Mini-design and responsibility map

```text
author -> sealed Outputs -> independent checks + fresh reviewer
                                     |
                      accept --------+-------- reject
                        |                        |
                 existing land/cleanup    reserve fresh author
                                          + findings/repro refs
                                                |
                                      new Outputs, new checks,
                                        fresh reviewer Run
```

- **Policy:** core evaluates current eligible actions from Board facts under
  an explicitly enabled, frozen policy. Routine check/reviewer/rework requests
  use existing operations and stable identities. Only the runtime owns external
  effects; the Pi extension displays progress and carries decision requests.
- **Bounds:** cap rework attempts and aggregate elapsed/resource consumption.
  A new Run does not silently reset the exp's policy allowance. Exhaustion,
  unresolved questions, changed acceptance, unexpected target movement or
  ambiguous launch stops and escalates; no automatic rebase or scope inference.
- **Controller disposition:** verify the review's load-bearing claims and bind
  accepted/disputed/needs-clarification findings to the exact packet/output.
  Optional human feedback retains its actual source/scope; ordinary rework does
  not wait for a human approval. Disagreement cannot erase a review or fabricate
  passing evidence. Exp 7 owns the context-fork/handoff contract, not this scheduler.
- **Independence:** reporting seals work. A rejected output gets a new author
  Run, which may inherit the prior reviewer's context through an explicit fork.
  That fixer cannot approve its own work. A new exact commit gets independent
  checks and a fresh reviewer Run/session without author/fixer conversation
  ancestry. Expired or superseded credentials never regain work authority.
- **Repro handoff:** the reviewer may produce isolated repro artifacts outside
  the reviewed source. The author adopts the smallest portable regression,
  records red-before/green-after evidence and fixes the implementation. Retain
  provenance to the original finding and exact rejected commit. Do not blindly
  commit scratch directories, temporary Boards, sessions, credentials or binaries.
- **Recovery:** persist reservations and operation identities before effects.
  Replayed events request the same action; a lost launch response is inspected,
  not permission to spawn again. Revalidate authority before every new effect.
  Human pause prevents new autonomous work without erasing existing obligations.

Existing code anchors are [`Board.apply`](../../../core/board/board.ml),
[launch reservation](../../../core/runtime/launcher.ml) and
[runtime ownership](../../../core/runtime/runtime.ml). Exp 2's
[operation homes](2026-11-05-auto-land.md#schema-v3-and-operation-homes-pinned-design)
define the candidate check/review/integration responsibilities. These are a
responsibility map, not a claim that the home runtime already schedules the loop.

## Acceptance and evidence

All checks below are **not run** for this exp.

1. A deliberately rejected toy output proceeds through a fresh author carrying
   the findings, a faithful permanent regression, a new exact submission,
   independent checks and fresh review. Original outputs/verdicts stay readable.
   No human performs routine scheduling and no model polls for completion.
2. Capture the regression failing against the rejected commit and passing on
   the fix. Keep actual harness-boundary behavior where a fake dispatcher would
   hide the failure. A separate intentionally red integration commit is not
   required; permanent tests and fixes may be submitted together.
3. Duplicate events, concurrent requests and runtime death before/after
   reservation or spawn yield at most one authorized attempt, or an explicit
   unresolved ambiguity. No silent respawn, self-approval or reused stale Review.
4. Repeated rejection hits a configured limit and yields one retained escalation
   rather than an endless author/reviewer token loop. Preserve all findings;
   unknown provider cost stays unknown.
5. Pause, cancellation, expiry, takeover, blockers and target movement prevent
   unauthorized next actions. Another launch request respects the existing
   one-author/one-reviewer maximum and shows why it is deferred/refused.
6. Closing the Controller leaves deterministic reconciliation alive; restoring
   it reconstructs the next decision from the Board through Exp 4's delivery
   path. No source changes, kernel activation, promotion or push follow from
   notification alone.

## Runbook, recovery and human touchpoints

Use a frozen candidate and disposable consumer/Board. Start with deterministic
actors to enumerate retry and limit cases, then separately authorize a bounded
visible Astra xhigh rehearsal. Record exact commits, check receipts, reviewer
identity, attempts and stop reasons through public operations, not pane text.

Disabling policy stops new orchestration actions, not already-authorized
runtime reconciliation or safe cleanup. Preserve frozen briefs, outputs and
obligations. A policy change must have explicit provenance; it cannot rewrite
an existing assignment or replenish its budget invisibly. The human decides
scope/acceptance changes, exhausted-budget escalation and eventual promotion.

## Red chair and next step

Strongest attack: an autonomous reject/fix loop spends indefinitely or gradually
weakens acceptance until it can claim success. Keep immutable checks and exact
review binding, aggregate attempt bounds, a visible stop reason and no authority
to amend scope or budget. Useful reviewer regressions remain part of current
Exp 2 fixes; only their automatic packaging/handoff is deferred here.
Before delegation, pin the minimal policy inputs, aggregate limits and safe
pause/restart semantics. Do not build a general scheduler first.
