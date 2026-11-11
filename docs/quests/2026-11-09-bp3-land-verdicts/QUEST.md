---
quest_type: default
engine: single
status: proposed
home_repo: bp3
date: 2026-11-09
---

# bp3-land-verdicts: the binary outputs for landing

TL;DR
The binary learns to feed the landing loop: one verdict shape
with a landing packet, an error envelope with retryable vs
terminal refusals, every refusal ledgered, and a re-entry
edge so a commit rebased after review can rejoin the state
machine. When this Quest lands, the `/land` skill from
[bp3-mvp-plugin-git-cas-lands](../2026-11-09-bp3-mvp-plugin-git-cas-lands/QUEST.md)
hardens from rebase-before-review into the full
observe → rebase → re-validate → CAS retry loop, driven
entirely by JSON and exit codes.

ELI5
Today the referee whispers over his shoulder: every mistake
is the same shout (exit 1, stderr prose), the scoreboard
doesn't say where the target stands, and a player who
rebased after being reviewed has no door back onto the field.
This Quest gives the referee a proper scoreboard and whistle
codes, and builds the re-entry door — so the clerk can loop
without guessing or reading lips.

## Concepts

- landing packet — the fields every read and edge verdict
  carries: `commit`, `target`, `target_sha`, `head`, `stale`,
  `passing_check`, plus today's `stage`, `cycle`,
  `ledger_seq`, `legal_moves`. One shape for reads and
  writes; `prepare` returns it too (no more plain text).
- error envelope — failures as JSON on stdout with a stable
  `error` code, human text on stderr. Exit codes: 0 success,
  2 retryable refusal, 1 terminal refusal, 3 usage/not-found.
- retryable refusal — exactly one today: `target_moved`
  (the CAS compare failed). The envelope carries the new
  `target_sha` so the loop re-bases without another read.
- terminal refusal — `illegal_move`, `no_passing_check`,
  `dirty`, `not_descendant`, `dependency_not_landed`, and
  kin. Ledgered like illegal moves already are; guard
  failures today are *not* ledgered — that changes here.
- re-entry edge — the legal move that accepts a rebased
  commit after `review`/`ready`, voiding verdicts bound to
  the superseded commit. Name and cycle semantics are this
  Quest's design work, not assumed.
- tree-identical rebase — a rebase whose resulting tree
  hash equals the reviewed commit's. Whether its verdicts
  may carry over is decided here, on the predecessor
  Quest's rebase data.

## Goal and why

The MVP land skill works because it narrowed itself to what
today's binary can express: rebase before review, stop on
refusal. The general landing problem — master moves after
review, clerk loops unattended — is inexpressible: no legal
edge accepts a rebased commit from `ready`; the skill cannot
distinguish "master moved, go again" from "stop forever"
without parsing stderr; and the read verdict omits target,
target SHA, HEAD, staleness, and passing-check, so any
driver must shell out to git and become a second source of
truth. This Quest fixes the binary's output surface, in that
order, so the loop runs on verdicts, not vibes.

## Success picture

The land skill, upgraded in Exp 3, lands a quest whose
target moves *after* review: `land` refuses with exit 2 and
`{"error":"target_moved","target_sha":...}`; the skill
re-enters the rebased commit through the new edge, re-runs
review and checks on it, and CAS-lands — no stderr parsing,
no direct git reads of refs the packet already reports, and
a ledger line for every refusal including guards. Landing
is recorded in the quest ledger with the same limitations
stated as the MVP's.

## Scope

In: unified verdict shape (landing packet on reads, edges,
and `prepare`); error envelope + exit codes (0/1/2/3);
ledgering guard refusals; the re-entry edge for rebased
commits; `land`-skill hardening to the full retry loop;
tree-identical carry-over decided on evidence.
Out: the binary performing rebases (it reports and judges,
executors rebase); speculative merge queues; concurrent
landings and clerk ordering (still one quest at a time);
new plan types; changes to `submit`'s existing guards.

## Human touchpoints

Quest framing (this file), the re-entry edge's name and
cycle semantics (Exp 2 design gate), the tree-identical
decision (Exp 2), and Quest-to-master promotion.

## Exps

### Exp 1 — Landing packet and error envelope

- Intent: every driver input and failure class becomes
  machine-readable in one shape.
- Lane: standard
- Output: `bp3 invoke` verdicts (read and all edges,
  `prepare` included) carrying the landing packet; failures
  as the error envelope with exit 0/1/2/3; guard refusals
  appended to the ledger with `result: "refused"` and the
  envelope's `error` code. Existing fields and ledger
  readers keep working (additive change).
- Acceptance: fixture drills — `land` with a moved target
  exits 2 with `error: "target_moved"` and the new
  `target_sha`, ledgered; `land` without a passing check
  exits 1 with `error: "no_passing_check"`, ledgered; an
  unknown quest exits 3; every success verdict parses
  against one jq schema for both reads and edges. Fails
  today: all failures exit 1 with stderr prose, guard
  refusals leave no ledger line, read and write verdict
  shapes differ, `prepare` prints plain text.
- Depends on: bp3-mvp-plugin-git-cas-lands Exp 1 (which
  refusals the MVP actually hit, in its exp records).

### Exp 2 — Re-entry edge for rebased commits

- Intent: a commit rebased after review rejoins the
  machine instead of being stranded at `ready`.
- Lane: high-blast-radius
- Output: one designed edge (name, legal stages, cycle
  semantics, and actor/provenance are designed at this
  exp's gate, not before) that accepts `--commit` from
  `review`/`ready` under the existing descendant and
  clean-tree guards, records the superseded commit in the
  ledger line, voids verdicts bound to it, and returns the
  quest to a stage where fresh review and `check` bind to
  the rebased commit. The tree-identical question is
  decided here with the predecessor's data: default stays
  "verdicts bind to the commit" unless the data argues
  otherwise.
- Acceptance: fixture — submit A, review ship, check pass,
  move the target, rebase to A′, take the re-entry edge,
  observe: stage back under review, `has_passing_check`
  false for A′, a fresh `check` on A′ required before
  `land`; verdicts recorded against A never satisfy A′.
  Fails today: no legal move from `ready` accepts a new
  commit.
- Depends on: Exp 1.

### Exp 3 — Land skill hardened: the full retry loop

- Intent: the clerk loops on verdicts alone.
- Lane: standard
- Output: `skills/land` upgraded: on `target_moved` (exit
  2), rebase onto the envelope's `target_sha`, re-enter
  via Exp 2's edge, re-review, re-check, retry — bounded
  (default: 3 attempts), then `block` and escalate. The
  skill makes no git ref reads the packet already covers
  and branches only on exit codes and envelope fields.
- Acceptance: the Success picture drill passes end to end
  on the toy fixture with the target moved twice; attempt
  count and every refusal visible in the ledger; a target
  that moves forever ends `blocked`, never landed, never
  silently resolved. Fails today: the binary surface of
  Exps 1–2 does not exist.
- Depends on: Exps 1–2; bp3-mvp-plugin-git-cas-lands
  landed.

## Scorecard

Per landing: CAS refusals absorbed, re-entry count,
re-review/re-check cost per landing, human interventions,
ledger lines per landing. Recorded in exp records from
ledger data; unmeasured values stated, never zero.

## Risks and red chair

- Strongest attack on the goal: "exit codes plus JSON is
  API design for an audience of one skill." What changed:
  the audience is every future executor (Pi, workflow
  children) the engine-core Quest promises interchangeability
  to; stderr prose makes each of them a parser author.
  Remaining open: whether 0/1/2/3 is the right granularity
  or collapses under a second retryable class.
- Strongest attack on Exp 2: the re-entry edge reopens
  verdict provenance (who may re-enter, does cycle bump,
  does a reviewer re-enter their own review?). What
  changed: name/semantics are an explicit human gate at
  the exp, with the fixture pinning "old verdicts never
  satisfy the new commit" as the non-negotiable.
- What remains open: one-quest-at-a-time is assumed
  throughout; a concurrent-landing world stresses the
  envelope (e.g. is `target_moved` still the only
  retryable?) and is deliberately not designed here.

## Open questions

1. Re-entry edge name and semantics: `retarget`, `resubmit`,
   or `submit` widened to `ready`? Owner: human, at the
   Exp 2 gate, with naming vocabulary applied.
2. Retry bound default (3) and what resets it. Owner:
   implementer, in Exp 3, from Exp 2 fixture data.
3. Tree-identical verdict carry-over: yes, no, or
   check-only? Owner: human, in Exp 2, on the predecessor
   Quest's rebase data.
