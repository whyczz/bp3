---
date: 2026-11-07
quest: ../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — Commit-state FSM

## TL;DR

An FSM in an FSM: a six-state Moore machine per exp over per-exp
ledgers at derivable branch tips, CAS landing with three
outcomes, the railway with autoland, and a human-gated
`resume`. Any executor can play.

Status: **proposed, not implemented or verified.**

## Demo (design traces — nothing here has run yet)

```text
HAPPY PATH (one exp, end to end)
  todo --submit c1--> submitted --review ship + check pass--> approved
       --engine autoland--> landed          (quest tip moves once)

BLOCKED RAILWAY (the human gate)
  submitted --needs_fix @ max_cycles--> blocked   [checkpoint committed]
  engine bubbles -> human: "resume, go simpler"
  blocked --resume (BP3_DECIDER=human)--> todo c2
  fresh author Run -> new commit -> submit -> review -> approved -> landed

POINTER RACE (nobody gets paged)
  exp A lands (quest tip moves) while exp B sits approved
  B autoland: clean merge -> landed, verdicts intact
              work conflict -> todo, cycle unchanged, rework
```

```text
                 submit
        todo --------------> submitted --ship+check--> approved
          ^                    |                            |
          | needs_fix          | needs_fix @ max_cycles     | land (autoland)
          +---- cycle+1        v                            v
          |                  blocked                     landed
          +---- resume (human)   |
                                 +-- delete (human) --> deleted
        block: any live state -> blocked        delete: any live -> deleted
```

```python
def judge(exp, edge, flags, who):
    state = fold(ledger at tip(exp.branch))       # truth lives at the tip
    if edge not in legal[state]: refuse(E_ILLEGAL_EDGE, legal_edges)
    if edge in (resume, delete_from_blocked) and who.decider != human:
        refuse(E_HUMAN_REQUIRED, "ask the human")
    return route(state, edge, flags)              # review/check may advance

def land(exp):
    if quest_tip is ancestor(exp_tip): fast_forward(quest_branch)
    elif merge_clean(exp_tip, quest_tip): merge_commit()   # verdicts stay true
    else: transition(exp, todo, cycle=unchanged)           # work conflict
```

## Tables

| Field | Value |
|---|---|
| Intent | Define state and moves so any executor can play |
| Lane | high-blast-radius |
| Output | The inner FSM, its storage in git, the railway, and the land operation |
| Depends on | Exp 2 |

States (conditions, never roles or commands):

| State | Meaning | Legal moves |
|---|---|---|
| `todo` | no commit under judgment | submit, block, delete |
| `submitted` | exact commit collecting verdicts | review, check, block, delete |
| `approved` | every required gate recorded | land, block, delete |
| `blocked` | a human decision is owed | resume, delete (both human-gated) |
| `landed` | terminal | — |
| `deleted` | terminal tombstone; ref kept | — |

Edges (the CLI `<edge>` under `u`; `delete` rides the `d` door):

| Edge | From -> to | Notes |
|---|---|---|
| `submit` | todo -> submitted | binds the exact commit |
| `review` | submitted | one multiplexer edge: `ship` stays/advances, `needs_fix` -> todo (cycle+1) or blocked at `max_cycles` |
| `check` | submitted | verdict recorded, may complete `approved` |
| `land` | approved -> landed | engine autolands; three outcomes below |
| `block` | live -> blocked | dirty-work checkpoint rule applies |
| `resume` | blocked -> todo | cycle+1 if a commit was in play; human-gated |

Storage and land:

| Rule | Value |
|---|---|
| Source of truth | ledger files at branch tips in git — nothing else |
| Branches | `bp3/quest/<quest>`, `bp3/exp/<quest>/<exp>` — derivable, slash-free slugs, short suffix only for generated/colliding names |
| Writes | one accepted transition = one ledger line (`ts` stamped) + one commit; CAS on the tip |
| Cache | `state.yaml` is derived from the ledger fold, rebuildable |
| Land outcome 1 | quest tip is ancestor: fast-forward |
| Land outcome 2 | quest tip moved, clean merge: merge commit; reviewed commit stays ancestor, verdicts stay true |
| Land outcome 3 | work-file conflict: exp returns to `todo`, cycle unchanged |
| Dirty work | committed as a checkpoint **only** on entering `blocked`; checkpoint sha rides the block line; judged by nobody |
| Quest landing | rollup may say “all entries terminal”; `landed` only by human promotion to master |

Plans and dimensions:

| Knob holder | Carries |
|---|---|
| Binary | the one compiled transition table; `stages:`/`edges:` keys in plans are rejected |
| `quest_type` | outer plan, knobs only (`max_cycles`, `depends_on`) |
| `exp_type` | inner profile: `review.required`, required checks, skill names Runs import |
| engine | per-Run system (FSM + harness); never a quest property |

## Acceptance (fails today: states are process labels, reports accepted unconditionally)

| Case | Expected |
|---|---|
| two executors alternate edges on one exp | identical guard behavior |
| verdict lands on commit A after B supersedes it | refused |
| review + check run in parallel in `submitted` | ledger serializes verdicts; advance happens once both gates record on the exact commit |
| `needs_fix` at `max_cycles` | `blocked`, engine halts and escalates — no ping-pong |
| two exps land into one quest branch | clean merge keeps verdicts; conflict demotes only the conflicting exp |
| session dies mid-railway | clone anywhere, fold tips, reproduce exp states + quest rollup + blocked inbox |
| pointer race under parallel agents | CAS loser re-reads and retries; no human paged, no demotion for staleness alone |

## Acceptance test (goal block)

- **Objective:** implement the six-state FSM and git storage
  specified above so any executor can take any legal edge.
- **Prove by:** scenario fixtures for every Acceptance case:
  alternating executors, stale-verdict refusal, parallel
  review/check on one commit, cycle-cap escalation, two-exp
  landings (merge and conflict paths), clone-and-reconstruct
  of states + rollup + inbox.
- **Done when:** all scenarios pass, and a fresh clone of the
  fixture repo reproduces every exp state from branch tips
  alone — no state.yaml trusted, no registry consulted.

## Context

The old machine named its states after people and activities,
so nobody could say what was true of an exp — only what
someone was doing near it. Moore naming fixes the question
each state answers: what is the condition, and therefore which
moves are legal here. Iteration became data (`cycle`) for the
same reason: a first submission and a third submission have
identical legal moves, and a machine that cannot tell its
states apart by their moves has too many states.

Storage is git because the whole point is archaeology and
portability: branches for quests, branches for exps, files
for truth, a clone rebuilding the world. The railway exists
because parallel landable exps were the overwrite risk — a
linear track with declared fan-out groups keeps exactly one
landable thing moving while still letting exploration run
side by side.

Resolving a blocked exp is skill choreography: the engine
presents facts and choices in the harness, captures the
human's words as `--reason`, attests `BP3_DECIDER=human`,
makes the resume/delete call, and dispatches a fresh Run.
The human neither calls bp3 nor supplies a commit.

Edge cases: rebase is legal only before submit, while no
verdicts exist — once a SHA has verdicts, it is frozen.
Refusals are JSON only, never ledger lines, so a misfiring
agent cannot spam a branch tip forward. A malformed ledger
stops the call with a named code; corruption gets a human,
never a silent repair. The quest rollup is derived from refs,
so no second write can disagree with it. The current
`invoke/main.ml` is a disposable prototype; implementation
files are written after this Quest is finalized.
