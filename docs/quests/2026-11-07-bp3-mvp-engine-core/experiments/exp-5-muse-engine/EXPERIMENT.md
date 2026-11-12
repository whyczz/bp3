---
date: 2026-11-11
quest: ../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Muse engine

## TL;DR

The dogfood engine: one `induct` skill, the `induct-exp`
saved workflow, and Muse hook settings. The skill loops a
quest's railway at the quest level; `induct-exp` loops one
exp's inner FSM at a time; `blocked` exps bubble to the
human-facing main session.
All state moves through `bp3 q u`; the engine never writes
state itself.

Status: **proposed, not implemented or verified.** Pulled into
this quest from the downstream bp3-mvp-muse-workflows quest
(red-ink, 2026-11-11); only its executor-test exp came
with it. First piece landed ahead of the
exp: the `induct` skill (`skills/induct/SKILL.md`, installed for
all harnesses 2026-11-11) — renamed from `drive` the same day,
since induction names its two-level loop. `induct-exp` and
the hook settings remain this exp's to build.

## Demos (design traces — nothing here has run yet)

Induct = one engine loop over a quest: read, dispatch Runs,
autoland, stop only at a terminal rollup or an owed human
decision. The traces below are the acceptance demos in
miniature; each maps to a case in the Acceptance table.

```text
DEMO 1 — HAPPY INDUCT (one toy exp, start to landed)
  human (main session): "induct quest toy"
  engine: bp3 q r toy                 -> parser-fix: todo, inbox: []
  child A (author): commits work c1
                  -> bp3 q toy u parser-fix submit --commit c1
  child B (review): bp3 q toy u parser-fix review --verdict ship  (commit c1)
  child C (check):  bp3 q toy u parser-fix check  --verdict pass  (commit c1)
  engine: state approved -> autoland -> bp3 q toy u parser-fix land
  engine: bp3 q r toy                 -> parser-fix: landed, rollup terminal
  induct stops. Ledger: 4 lines, harness=muse-code on each.
  Scorecard: wall time + tokens per Run, from tapes/usage markers.

DEMO 2 — FORCED BLOCK + HUMAN RESUME (the human gate)
  child B review --verdict needs_fix at max_cycles
                  -> blocked [dirty-work checkpoint committed]
  induct stops (railway blocked; exps behind parser-fix untouched)
  main session bubbles: "parser-fix blocked: <reason> — resume or delete?"
  bp3 q r toy -> inbox: [{quest: toy, exp: parser-fix,
                          reason, checkpoint, cycle, since}]
  human: "resume, go simpler"
  engine attests BP3_DECIDER=human
                  -> bp3 q toy u parser-fix resume --reason "resume, go simpler"
                  -> todo c2 -> fresh child A' dispatched (new Run id)
  (no human resume -> resume refused E_HUMAN_REQUIRED; induct stays stopped)

DEMO 3 — CHILD MISFIRE (guards bite the engine too)
  child B (confused): bp3 q toy u parser-fix land   (from submitted)
                  -> {"ok":false,"error":{"code":"E_ILLEGAL_EDGE",
                      "facts":{"state":"submitted","legal_edges":
                      ["review","check","block"]},"guidance":"..."}}
  nothing ledgered, state unchanged; the step made no progress,
  so induct-exp exits {outcome: refused} and induct re-reads,
  re-judges, and dispatches a legal edge. Engine earns no
  exemptions: same refusal any caller gets.

DEMO 4 — SESSION DIES MID-INDUCT (recovery is a fresh induct)
  main session killed while child B is mid-review
  child finishes or dies; tape survives either way (Exp 4 tee)
  human reopens Muse anywhere on a fresh clone
  engine: bp3 q r toy -> states folded from branch tips
         (submitted c1, review verdict present or absent as ledgered)
  induct resumes by respawning the missing edge. No script resumed,
  no state recovered from the dead session's memory.

DEMO 5 — FAN-OUT GROUP (exploration pauses for a human choice)
  railway: [exp-a, {explore-x | explore-y}, follow-up]
  induct lands exp-a, reaches the group, stops:
    "run explore-x, explore-y, or both? members are not landable"
  human: "both" -> children run in parallel on separate exp branches
  both settle -> induct stops again: "which result feeds follow-up?"
  human picks -> follow-up exp created from that result -> induct continues

DEMO 6 — RUN ZERO (observed, informal — this quest's own build)
  Exps 2–4 of this quest are built by a human-driven Muse
  session using workflows/subagents before Exp 5 exists.
  Recorded as observed evidence: what choreography the human
  actually used, where it hurt, scorecard gaps stated.
  Exp 5 formalizes that choreography into the single `induct`
skill and `induct-exp`; Demo 1–5 then re-run
  formally on the toy quest. Run zero never counts as a pass
  of Demos 1–5 — it is their field notes.
```

```text
human <-> main session (engine skills live here)
              |  navigate railway, bubble blocked, attest human
              v
        induct-exp -------- dispatches ----> workflow children (per edge)
              |                                   | bp3 q u only
              v                                   v
        Muse hooks ----------------> ledger lines (facts, Exp 4)
        tape (Exp 4) <---- tee ---- child output (verbatim, evidence)
```

```python
def induct(quest):                             # THE skill; main session; outer loop
    while True:
        view = bp3_q_r(quest)                 # railway + blocked inbox, live
        if view.inbox:
            decision = bubble_to_human(view.inbox[0])   # human's words
            bp3_q_u(view.inbox[0], decision.edge,
                    reason=decision.words, decider="human")   # attested
            continue                          # fresh Runs dispatched next loop
        nxt = next_on_railway(view.railway)
        if nxt is None:
            return view.rollup                # terminal: induct stops
        if nxt.is_fanout_group:
            members = ask_human(nxt)          # induct stops until answered
            induct_exp(quest, members)        # exploration only, not landable
            continue
        outcome = induct_exp(quest, exp=nxt)  # one exp per invocation
        # loop re-reads before any next dispatch — the return is never state

def induct_exp(quest, exp):                   # `induct-exp`; inner-FSM loop
    before = bp3_q_r(quest, exp)
    if before.state in ("landed", "blocked", "deleted"):
        return before.state                   # base case (exit)
    children = [spawn_child(edge) for edge in next_edges(before)]
    results = parallel(children)              # review || check on one commit
    after = bp3_q_r(quest, exp)
    if after.state in ("landed", "blocked", "deleted"):
        return after.state                    # base case reached by the step
    if unchanged(before, after):              # same state/commit/cycle
        return {"outcome": "refused", "refusals": results.refusals}
    return induct_exp(quest, exp)             # step landed; go again
    # named for the induction: current state is the hypothesis, one
    # legal step is the inductive step, a terminal-or-human state
    # is the base case, and no progress exits instead of spinning
```

## Tables

| Field | Value |
|---|---|
| Intent | Prove one real engine can induct the railway end to end, and dogfood it on this quest's own build |
| Lane | high-blast-radius |
| Output | Engine bundle: the single `induct` skill (quest-level loop, resolve-blocked included), the `induct-exp` saved workflow (inner-FSM loop, one exp per invocation), Muse hook settings, and the installer extension that delivers them; plus the run-zero record of this quest's own build |
| Depends on | Exp 2 + Exp 3 + Exp 4 |

Induct input is the quest-level `induct(quest)` contract in
[QUEST.md](../QUEST.md#induct); this exp implements whatever
that contract requires underneath it.

Distribution (settled): a bp3-enabled repo gets the whole
engine from one install.

| Piece | Source in bp3 | Installed to | By |
|---|---|---|---|
| `induct` skill | `skills/induct/SKILL.md` | per-harness skill dirs (exists today) | `bp3 skills install` (exists today) |
| `induct-exp` workflow | `skills/induct/workflows/induct-exp.js` | `.agents/workflows/induct-exp.js` — the same path `muse workflows save --scope project` writes (probed 2026-11-11) | `bp3 skills install`, extended by this exp; copied, never hand-edited at the target |
| Hook settings | this exp's Muse settings fragment | the repo's Muse settings | `bp3 skills install`, extended by this exp |

The installer extension is small shell in `bin/bp3` with
fixture coverage in `test/skills.sh`, in the same style as
the skill renders: preflight, copy, verify. Installing never
requires the `muse` CLI to be present.

Workflow grain (settled): **one workflow invocation per exp.**

| Grain | Rule |
|---|---|
| Invocation | `induct_exp(quest, exp)` (saved workflow `induct-exp`) carries one exp from its current state to an exit below |
| Exits | `landed` (done), `blocked` (human owed), `deleted` (tombstone, done), `refused` (state/commit/cycle unchanged after a step — `induct` re-reads and re-judges; the loop never spins on an unchanged state) |
| Inside | one child per edge (author, review, check); review + check children may run in parallel on the same commit in `submitted`; autoland is the workflow's last step at `approved` |
| Between exps | the workflow returns; the `induct` skill re-reads `bp3 q r` and decides the next dispatch — choreography never crosses an exp boundary inside one workflow |
| Session death | loses at most one exp's in-flight choreography; state is rebuilt from branch tips and the missing edge is respawned by a fresh induct |

Data crossings (settled):

| Crossing | Shape | Rule |
|---|---|---|
| skill → workflow | `{quest, exp}` | everything else is read via `bp3 q r` inside the run |
| child → ledger | children call `bp3 q u` directly | verdicts persist at the moment they happen (Exp 4); never only in a return value |
| workflow → skill | summary only: `{exp, outcome, run_ids, refusals}` | a hint, never state — the induct re-reads `bp3 q r` before its next decision, so a child that dies after its CLI call lands loses nothing |
| fallback | relay-via-parent, only if Acceptance probe 13b proves children cannot reach the CLI | adopted with its identity cost (child work attributed to the parent) stated in this record, never silently |

Engine parts (core/plugin test from the quest applies):

| Part | Core or plugin | Why |
|---|---|---|
| `induct` skill — railway navigation | core | No navigation, no travel |
| `induct` skill — resolve-blocked procedure (bubble, capture, attest, redispatch) | core | The human gate lives here; a section of `induct`, never a second skill |
| `induct-exp` workflow — loops one exp's inner FSM, one child per edge | core | The hands that take edges |
| Muse hook settings (Exp 4 fact emission) | core | Facts must land at the moment they happen |
| Notifications beyond the main session | plugin | Engine dies, exp still travels; frozen as future work in the quest's plugin contract |

Workflow API facts this design must honor (from the
[muse-workflows-hooks dossier](../../../../dossiers/muse-workflows-hooks.md),
2026-11-07, unprobed live):

| Fact | Consequence |
|---|---|
| Children are ephemeral, unsteerable mid-flight | Block means block-then-respawn; a blocked child is never resumed in place |
| No per-call model routing in one workflow | Model per Run comes from the parent session; routing claims wait for probe evidence |
| Child CLI reach is unprobed | Exp must probe: child calls `bp3 q` directly, or relays verdicts via the parent |
| Workflow returns one JSON value to the parent | Edge verdicts persist through `bp3 q u`, never only in the return value |

## Acceptance (fails today: no Muse engine, no `induct-exp`, no live run)

Each case maps to a demo above. A case passes only on
recorded artifacts (ledger lines, tapes, verdict JSON), never
on the main session's say-so.

| # | Case (demo) | Expected |
|---|---|---|
| 1 | Happy induct (D1) | `todo → landed` on the toy exp; exactly 4 ledger lines (submit, review, check, land); every line `harness: muse-code`; rollup terminal; induct stops without human input |
| 2 | Forced block (D2) | `needs_fix` at `max_cycles` → `blocked`; checkpoint sha on the block line; exps behind it on the railway untouched; inbox entry present in `bp3 q r` JSON and table |
| 3 | Human resume (D2) | `resume` without human attestation → `E_HUMAN_REQUIRED`, nothing ledgered; with attestation → `todo`, cycle+1, fresh Run id dispatched; human's words recorded as `--reason` verbatim |
| 4 | Delete from blocked (D2 variant) | Human-gated `delete` → `deleted` tombstone; branch ref kept; induct proceeds past it or stops per railway position — behavior recorded, not improvised |
| 5 | Child misfire (D3) | Illegal edge from a child → refusal JSON with code/facts/guidance; ledger length unchanged; induct continues on a legal edge |
| 6 | Stale verdict (D3 variant) | Review naming commit A after B superseded it → `E_COMMIT_MISMATCH`; no advance toward `approved` |
| 7 | Session dies mid-induct (D4) | Kill the main session mid-review; fresh clone + fresh induct reproduces every exp state from branch tips alone; missing edge respawned; no state recovered from session memory |
| 8 | Child killed mid-edge (D4 variant) | Tape complete up to the kill; unsettled tape not mistaken for state; respawn produces a distinct Run folder |
| 9 | Fan-out group (D5) | Induct stops at the group and asks; members run only after the human's choice; no member is landable (`land` → refusal); follow-up created only from the human-picked result |
| 10 | Parallel children, one exp | Review + check children race in `submitted`; ledger serializes both verdicts on the exact commit; `approved` reached once, never twice |
| 11 | CAS race across exps | Two exps autoland into one quest branch back to back; clean merge keeps verdicts, or conflict demotes only the conflicting exp to `todo` (cycle unchanged); no human paged |
| 12 | Identity honesty | Every engine-taken ledger line records the model actually used; unset identity → `unknown` + `W_IDENTITY_UNKNOWN`, never a guessed model name |
| 13 | Probes | (a) V8 workflow executes on this machine — `induct-exp` runs, child returns; (b) child CLI reach: child calls `bp3 q` directly, or the relay-via-parent shape is adopted with the probe transcript as evidence; (c) per-call model routing: proven working, or priced (separate parents) with numbers, or recorded absent |
| 14 | Run zero (D6) | This quest's Exp 2–4 build recorded as observed run zero: choreography used, demos captured per exp, scorecard fields filled or explicitly "unmeasured"; run zero is cited as field notes, never as a pass of cases 1–13 |
| 15 | Scorecard | Per Run: wall time, context tokens (or "unmeasured"), human-active minutes, interventions; recorded in this record and rolled into the quest Scorecard — no zeros for unmeasured values |
| 16 | No-progress step (D3 variant) | Children refused or produce no commit; state/commit/cycle unchanged → `induct-exp` exits `{outcome: refused}` after one step (run count proves no spin); induct re-reads and re-judges before any new dispatch; exp deleted mid-run → `deleted` exit, no further children spawned |
| 17 | Distribution | In a scratch repo, `bp3 skills install` delivers the `induct` render, `.agents/workflows/induct-exp.js`, and hook settings; `muse workflows list` sees `induct-exp`; removing the workflow makes `induct` stop and say so instead of improvising |

## Acceptance test (goal block)

- **Objective:** build the Muse engine bundle above and
  induct a toy quest exp `todo → landed` with it, blocked
  bubble included.
- **Prove by:** Demos 1–6 executed on a toy quest (happy
  induct, forced block + human resume, child misfire, session
  death, fan-out pause) plus the probe transcripts — every
  Acceptance case (1–17) evidenced by ledger lines, tapes,
  or verdict JSON left on disk.
- **Done when:** all 17 Acceptance cases pass on recorded
  artifacts, the toy quest's ledger shows every edge taken by
  a workflow child through `bp3 q u`, and the run-zero record
  for this quest's own build is written with its gaps stated.

## Context

This exp existed downstream as a test of whether ephemeral
workflow children can honor a contract built on durable
state. Pulling it into the MVP turns the test into the tool:
the engine that proves the railway is the engine that runs
this quest's own construction. That is the dogfood loop —
Exps 2–4 get built by hand-driven Muse workflows first
(run zero, informal, recorded honestly), then this exp
formalizes the choreography that worked into the `induct`
skill, `induct-exp`, and hooks.

How we got here: the predecessor quest's pane crews made
every Run re-buy its context, and four-hour bounces were the
bill. Workflow children fan out inside one session's context
economy instead — if they can be trusted with edges. The
guards are the same ones every executor faces; the engine
earns no exemptions, and a child misfiring into
`E_ILLEGAL_EDGE` is the CLI doing its job, not an engine
failure.

Edge cases: a workflow run that dies with its session leaves
state at branch tips — recovery is a fresh `induct`, never a
resumed script. Two children racing one exp serialize on the
ledger CAS; the loser re-reads and re-judges (Exp 3). Model
routing by role is out until the probe prices separate parent
sessions. Steering a running child is out — the API does not
offer it, and block-then-respawn is the specified shape.
