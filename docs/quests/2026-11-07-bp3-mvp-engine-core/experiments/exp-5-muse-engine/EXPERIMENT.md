---
date: 2026-11-11
quest: ../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Muse engine

## TL;DR

The dogfood engine: Muse skills, a saved workflow, and
Muse hook settings that drive a quest's railway — navigating
exps, dispatching workflow children per edge, autolanding at
`approved`, and bubbling `blocked` exps to the human-facing
main session. All state moves through `bp3 q u`; the engine
never writes state itself.

Status: **proposed, not implemented or verified.** Pulled into
this quest from the downstream bp3-mvp-muse-workflows quest
(red-ink, 2026-11-11); its Pi interchange exp did not come
with it — no Pi in this MVP. First piece landed ahead of the
exp: the `drive` skill (`skills/drive/SKILL.md`, installed for
all harnesses 2026-11-11) — the destination kept the name
`drive`, since the loop has somewhere to go. The saved
workflow and hook settings remain this exp's to build.

## Demos (design traces — nothing here has run yet)

Drive = one engine loop over a quest: read, dispatch Runs,
autoland, stop only at a terminal rollup or an owed human
decision. The traces below are the acceptance demos in
miniature; each maps to a case in the Acceptance table.

```text
DEMO 1 — HAPPY DRIVE (one toy exp, start to landed)
  human (main session): "drive quest toy"
  engine: bp3 q r toy                 -> parser-fix: todo, inbox: []
  child A (author): commits work c1
                  -> bp3 q toy u parser-fix submit --commit c1
  child B (review): bp3 q toy u parser-fix review --verdict ship  (commit c1)
  child C (check):  bp3 q toy u parser-fix check  --verdict pass  (commit c1)
  engine: state approved -> autoland -> bp3 q toy u parser-fix land
  engine: bp3 q r toy                 -> parser-fix: landed, rollup terminal
  drive stops. Ledger: 4 lines, harness=muse-code on each.
  Scorecard: wall time + tokens per Run, from tapes/usage markers.

DEMO 2 — FORCED BLOCK + HUMAN RESUME (the human gate)
  child B review --verdict needs_fix at max_cycles
                  -> blocked [dirty-work checkpoint committed]
  drive stops (railway blocked; exps behind parser-fix untouched)
  main session bubbles: "parser-fix blocked: <reason> — resume or delete?"
  bp3 q r toy -> inbox: [{quest: toy, exp: parser-fix,
                          reason, checkpoint, cycle, since}]
  human: "resume, go simpler"
  engine attests BP3_DECIDER=human
                  -> bp3 q toy u parser-fix resume --reason "resume, go simpler"
                  -> todo c2 -> fresh child A' dispatched (new Run id)
  (no human resume -> resume refused E_HUMAN_REQUIRED; drive stays stopped)

DEMO 3 — CHILD MISFIRE (guards bite the engine too)
  child B (confused): bp3 q toy u parser-fix land   (from submitted)
                  -> {"ok":false,"error":{"code":"E_ILLEGAL_EDGE",
                      "facts":{"state":"submitted","legal_edges":
                      ["review","check","block"]},"guidance":"..."}}
  nothing ledgered, state unchanged; child picks a legal edge.
  Engine earns no exemptions: same refusal any caller gets.

DEMO 4 — SESSION DIES MID-DRIVE (recovery is a fresh drive)
  main session killed while child B is mid-review
  child finishes or dies; tape survives either way (Exp 4 tee)
  human reopens Muse anywhere on a fresh clone
  engine: bp3 q r toy -> states folded from branch tips
         (submitted c1, review verdict present or absent as ledgered)
  drive resumes by respawning the missing edge. No script resumed,
  no state recovered from the dead session's memory.

DEMO 5 — FAN-OUT GROUP (exploration pauses for a human choice)
  railway: [exp-a, {explore-x | explore-y}, follow-up]
  drive lands exp-a, reaches the group, stops:
    "run explore-x, explore-y, or both? members are not landable"
  human: "both" -> children run in parallel on separate exp branches
  both settle -> drive stops again: "which result feeds follow-up?"
  human picks -> follow-up exp created from that result -> drive continues

DEMO 6 — RUN ZERO (observed, informal — this quest's own build)
  Exps 2–4 of this quest are built by a human-driven Muse
  session using workflows/subagents before Exp 5 exists.
  Recorded as observed evidence: what choreography the human
  actually used, where it hurt, scorecard gaps stated.
  Exp 5 formalizes that choreography; Demo 1–5 then re-run
  formally on the toy quest. Run zero never counts as a pass
  of Demos 1–5 — it is their field notes.
```

```text
human <-> main session (engine skills live here)
              |  navigate railway, bubble blocked, attest human
              v
        saved workflow ---- dispatches ----> workflow children (per edge)
              |                                   | bp3 q u only
              v                                   v
        Muse hooks ----------------> ledger lines (facts, Exp 4)
        tape (Exp 4) <---- tee ---- child output (verbatim, evidence)
```

```python
def drive(quest):                             # the `drive` skill; main session
    while True:
        view = bp3_q_r(quest)                 # railway + blocked inbox, live
        if view.inbox:
            decision = bubble_to_human(view.inbox[0])   # human's words
            bp3_q_u(view.inbox[0], decision.edge,
                    reason=decision.words, decider="human")   # attested
            continue                          # fresh Runs dispatched next loop
        nxt = next_on_railway(view.railway)
        if nxt is None:
            return view.rollup                # terminal: drive stops
        if nxt.is_fanout_group:
            members = ask_human(nxt)          # drive stops until answered
            run_workflow(quest, members)      # exploration only, not landable
            continue
        run_workflow(quest, exp=nxt)          # children take the legal edges
        # loop re-reads: approved -> autoland, blocked -> inbox, landed -> next
```

## Tables

| Field | Value |
|---|---|
| Intent | Prove one real engine can drive the railway end to end, and dogfood it on this quest's own build |
| Lane | high-blast-radius |
| Output | Engine bundle: railway + resolve-blocked skills, one saved workflow, Muse hook settings; plus the run-zero record of this quest's own build |
| Depends on | Exp 2 + Exp 3 + Exp 4 |

Drive input is the quest-level `drive(quest)` contract in
[QUEST.md](../QUEST.md#drive); this exp implements whatever
that contract requires underneath it.

Engine parts (core/plugin test from the quest applies):

| Part | Core or plugin | Why |
|---|---|---|
| Railway navigation skill | core | No navigation, no travel |
| Saved workflow (dispatch children per edge) | core | The hands that take edges |
| Resolve-blocked choreography (bubble, capture, attest, redispatch) | core | The human gate lives here |
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

## Acceptance (fails today: no Muse engine, no saved workflows, no live run)

Each case maps to a demo above. A case passes only on
recorded artifacts (ledger lines, tapes, verdict JSON), never
on the main session's say-so.

| # | Case (demo) | Expected |
|---|---|---|
| 1 | Happy drive (D1) | `todo → landed` on the toy exp; exactly 4 ledger lines (submit, review, check, land); every line `harness: muse-code`; rollup terminal; drive stops without human input |
| 2 | Forced block (D2) | `needs_fix` at `max_cycles` → `blocked`; checkpoint sha on the block line; exps behind it on the railway untouched; inbox entry present in `bp3 q r` JSON and table |
| 3 | Human resume (D2) | `resume` without human attestation → `E_HUMAN_REQUIRED`, nothing ledgered; with attestation → `todo`, cycle+1, fresh Run id dispatched; human's words recorded as `--reason` verbatim |
| 4 | Delete from blocked (D2 variant) | Human-gated `delete` → `deleted` tombstone; branch ref kept; drive proceeds past it or stops per railway position — behavior recorded, not improvised |
| 5 | Child misfire (D3) | Illegal edge from a child → refusal JSON with code/facts/guidance; ledger length unchanged; drive continues on a legal edge |
| 6 | Stale verdict (D3 variant) | Review naming commit A after B superseded it → `E_COMMIT_MISMATCH`; no advance toward `approved` |
| 7 | Session dies mid-drive (D4) | Kill the main session mid-review; fresh clone + fresh drive reproduces every exp state from branch tips alone; missing edge respawned; no state recovered from session memory |
| 8 | Child killed mid-edge (D4 variant) | Tape complete up to the kill; unsettled tape not mistaken for state; respawn produces a distinct Run folder |
| 9 | Fan-out group (D5) | Drive stops at the group and asks; members run only after the human's choice; no member is landable (`land` → refusal); follow-up created only from the human-picked result |
| 10 | Parallel children, one exp | Review + check children race in `submitted`; ledger serializes both verdicts on the exact commit; `approved` reached once, never twice |
| 11 | CAS race across exps | Two exps autoland into one quest branch back to back; clean merge keeps verdicts, or conflict demotes only the conflicting exp to `todo` (cycle unchanged); no human paged |
| 12 | Identity honesty | Every engine-taken ledger line records the model actually used; unset identity → `unknown` + `W_IDENTITY_UNKNOWN`, never a guessed model name |
| 13 | Probes | (a) V8 workflow executes on this machine — saved workflow runs, child returns; (b) child CLI reach: child calls `bp3 q` directly, or the relay-via-parent shape is adopted with the probe transcript as evidence; (c) per-call model routing: proven working, or priced (separate parents) with numbers, or recorded absent |
| 14 | Run zero (D6) | This quest's Exp 2–4 build recorded as observed run zero: choreography used, demos captured per exp, scorecard fields filled or explicitly "unmeasured"; run zero is cited as field notes, never as a pass of cases 1–13 |
| 15 | Scorecard | Per Run: wall time, context tokens (or "unmeasured"), human-active minutes, interventions; recorded in this record and rolled into the quest Scorecard — no zeros for unmeasured values |

## Acceptance test (goal block)

- **Objective:** build the Muse engine bundle above and
  drive a toy quest exp `todo → landed` with it, blocked
  bubble included.
- **Prove by:** Demos 1–6 executed on a toy quest (happy
  drive, forced block + human resume, child misfire, session
  death, fan-out pause) plus the probe transcripts — every
  Acceptance case (1–15) evidenced by ledger lines, tapes,
  or verdict JSON left on disk.
- **Done when:** all 15 Acceptance cases pass on recorded
  artifacts, the toy quest's ledger shows every edge taken by
  a workflow child through `bp3 q u`, and the run-zero record
  for this quest's own build is written with its gaps stated.

## Context

This exp existed downstream as a test of whether ephemeral
workflow children can honor a contract built on durable
state. Pulling it into the MVP turns the test into the tool:
the engine that proves the railway is the engine that drives
this quest's own construction. That is the dogfood loop —
Exps 2–4 get built by hand-driven Muse workflows first
(run zero, informal, recorded honestly), then this exp
formalizes the choreography that worked into skills, a saved
workflow, and hooks.

How we got here: the predecessor quest's pane crews made
every Run re-buy its context, and four-hour bounces were the
bill. Workflow children fan out inside one session's context
economy instead — if they can be trusted with edges. The
guards are the same ones every executor faces; the engine
earns no exemptions, and a child misfiring into
`E_ILLEGAL_EDGE` is the CLI doing its job, not an engine
failure.

Edge cases: a workflow run that dies with its session leaves
state at branch tips — recovery is a fresh `drive`, never a
resumed script. Two children racing one exp serialize on the
ledger CAS; the loser re-reads and re-judges (Exp 3). Model
routing by role is out until the probe prices separate parent
sessions. Steering a running child is out — the API does not
offer it, and block-then-respawn is the specified shape.
