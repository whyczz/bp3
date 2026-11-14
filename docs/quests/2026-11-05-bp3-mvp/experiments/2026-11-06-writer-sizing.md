---
date: 2026-11-06
quest: ../QUEST.md
exp: 6
status: proposed
---

# Exp 6 — Explicit writer configuration and sizing

## TL;DR

Make writer model/thinking selection explicit, inspectable and reproducible.
Start with a small manual sizing policy and per-launch selection, not an
adaptive routing framework. Keep Astra xhigh as the writer default unless the
human explicitly changes it; never silently fall back to Sol medium.

Status: **proposed follow-up, not implemented or verified**. The human already
allowed hardcoded `openai/gpt-6-astra:xhigh` for the current iteration and deferred
sizing. This record captures that backlog, not a change to active/frozen Runs.
Default scheduling is after Exp 3; it does not technically depend on Exps 4/5
and is not an additional MVP acceptance gate.

## Context and scope

At home checkpoint `e442374f9866b639078ed9f688c1f752d45a35df`, the launch payload
already accepts an optional `model` string and forwards it to Pi. Exp 2's
separate candidate explicitly launches Astra xhigh; that candidate is not yet
accepted or activated. Existing model selection does not establish a sizing
policy or prove the requested model/thinking actually ran.

In: explicit writer selection, a minimal documented sizing recommendation,
frozen resolved launch identity and requested-versus-observed verification.
Out: automatic downgrades, cost-optimizing classifiers, warm-pool scheduling,
provider benchmarking, multiple harnesses or higher concurrency. Reviewer
selection remains explicit and independent; writer settings do not silently
change reviewer identity or weaken review requirements.

## Mini-design and code tour

1. Resolve the documented precedence between an explicit per-launch choice and
   the default writer policy. Keep the current Astra xhigh default; reject
   conflicting or unsupported choices before work delivery.
2. Freeze resolved provider/model/thinking plus policy provenance with the
   assignment/launch identity. A retry uses the same resolution even if the
   default later changes. A different selection requires a fresh explicit
   assignment/Run, not a historical row or brief rewrite.
3. Compare requested selection to structured observed Pi session metadata.
   Ready/mounted/watchable and observed model identity remain different facts.
   An unavailable model, unsupported thinking level or mismatch holds/refuses
   work visibly; no fallback to a different model without authorization.
4. Recommend a size from the work's scope, uncertainty and risk, initially by
   explicit human/Controller choice. A recommendation alone cannot override
   the selected writer model. Record latency/quality/cost observations where
   available before proposing any adaptive routing policy.

Existing anchors: [launch CLI ingress](../../../core/control/main.ml),
[model argv construction](../../../core/runtime/launcher.ml) and
[Worker ready metadata](../../../plugins/harness-pi/bridge.ts). The installed Pi
model/thinking configuration must be checked before implementation. No proposed
profile names, new CLI flags or persistence fields are claimed to exist today.

## Acceptance and evidence

All checks below are **not run** for this exp.

- An unspecified writer selection resolves to Astra xhigh; an explicitly
  authorized alternate selection resolves predictably. The public Run view
  explains requested/resolved/observed identity without exposing credentials.
- A live brief-held writer demonstrates actual model and thinking identity
  before paid task delivery. Keep its own mounted tab in the Controller's bound
  Zellij session; configuration must not undo the existing visibility contract.
- Unknown profiles, unavailable models, unsupported thinking and observed
  mismatches cannot silently start Sol medium or another default.
- Changing defaults between retries does not change an existing launch. A
  conflicting request is rejected; older records remain unchanged.
- A small set of real briefs produces inspectable sizing recommendations and
  explicit choices, with unknown costs stated as unknown. Any claimed benefit
  requires measured evidence, not token-price assumptions or model branding.

## Runbook, recovery and human touchpoints

Freeze exact source and configuration at delegation. Test resolution/retry
behavior without provider calls first; separately authorize a brief-held live
identity drill. A launch/configuration failure remains inspectable and must not
blindly respawn. Reverting policy changes affects future assignments only;
active/frozen Runs retain their authority and selected identity.

The human owns changes to the default and allowed substitutions. This record
authorizes no launch, commit, activation, master promotion or push.

## Red chair and next step

Strongest attack: sizing becomes an elaborate router that silently chooses a
cheaper, unwanted writer. Keep selection explicit and auditable; defer adaptive
optimization until quality/rework observations support it. Before delegation,
pin the smallest useful configuration surface and precedence rules. Existing
Astra xhigh selection is sufficient to finish Exp 2.
