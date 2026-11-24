---
name: red-ink
description: "Present an existing design back to its owner in rounds until they say they are happy: copy the design first (original untouched), open with a greentext TL;DR + PRFAQ-style 10k-ft Shape demo, walk output, inputs, internals (data, state, functions, names, concepts), and close with Plan (nodes — with optional zoom-in on any node); every round is Observe -> Orient -> Decide (one question) -> Act -> IIUC, ending with a closing red chair and full Exit pack. Use for Socratic design review of an existing artifact. Not for one-shot adversarial review (red-chair), authoring a new design (design), or interviewing an unclear request (ask, grill)."
---
<!-- GENERATED from skills/red-ink/SKILL.md by: bp3 skills install --harness=agy. Edit the source, then re-run. -->

# Red ink

```text
existing artifact
    |
    +-- copy --> working copy        (original stays untouched)
                     |
    walk:  shape (10k-ft) -> output -> inputs -> data -> state -> fn -> names -> concepts -> plan (nodes)
                     |
    per slice: Observe -> Orient -> Decide -> Act -> IIUC
                     |
    owner: "happy / settle"
                     v
    decision record + proposed nodes
```

```python
def red_ink(artifact, expert=None):
    copy = duplicate(artifact)           # original never edited
    icebox_hits = search_icebox(artifact)  # where we want to get to
    for slice in [shape, output, inputs, data, state, fn, names, concepts, plan]:
        teach(slice)                     # Observe
        orient(slice)                    # the 2-4 things that matter
        decision = ask_one(owner)        # Decide: options + recommendation
        apply_one_edit(copy, decision)   # Act
        playback()                       # IIUC: settled / changed / open
        if owner.happy:
            break
    chair = red_chair(copy)              # closing pass on the settled design
    nodes = nodes + [concern_node(c) for c in chair
                          if c.severity in (critical, major)]
    return exit_pack(decisions, open_questions, nodes, chair)
```

## Context

Reading map for this skill: prose carries context, why, and how
we got here. Diagrams, pseudocode, and tables carry what we do.

Designs die in review when the owner gets the whole blob at
once: the read turns into a rubber stamp, and the objections
surface mid-build, priced as migrations. Red ink slows the
review down to one slice at a time so each decision lands
while changing it still costs a sentence.

How we get there shapes the walk below. Output goes first
because a design that emits the wrong thing earns no points
for elegant internals. One question per round keeps decisions
from smearing into each other. The original stays untouched
because a review that rewrites its own evidence can never be
re-run. The IIUC closes each round because the owner's
cheapest correction arrives right after the read, not three
slices later.

## Icebox awareness

Deferred direction is context, and it already lives somewhere:
before round one, search the icebox (`docs/icebox/` where the
repo has one) for entries naming this artifact, its quest or
node, or its concepts. Present hits in round one's Observe as
"where we want to get to" — frozen sketches with promotion
triggers, read for direction, never treated as settled design.
When a round defers something, the deferral lands as an
icebox entry (written with `/icebox` discipline, linked from
the working copy), not as a prose line that evaporates at
settle. The exit pack names every entry consulted and every
entry frozen.

## When this fires

| Case | Fire |
|---|---|
| `/red-ink`, “walk me through this design” | this skill |
| one-shot adversarial pass, no loop | `red-chair` |
| written four-pass review the owner reads alone | `red-chair-design` |
| no design exists yet | `design` |
| the request itself is unclear | `ask` / `grill` |

## The walk

Before drilling into schemas or flags, start with the **10,000-foot
Shape gate** (`Shape` is slice 1, before `Output`):
1. **Context & Why (greentext TL;DR opener):** why this exists,
   what pain it kills, and how it fits the rest of the system.
2. **PRFAQ-style Demo (already built):** present the feature as if
   it already shipped — 2–4 concrete day-to-day use cases showing
   what you type, what you see, and what action happens at the end
   (honestly labeled `design trace`).
3. **Architecture & mechanism bet:** state plainly *how* it works
   at 10,000 ft (e.g. deterministic rules middleware vs LLM-as-a-judge
   vs hybrid, and what concrete artifact/action it produces) so the
   owner settles the big bet before debating JSON keys or flags.
4. **Opening attack** (see Red chair at the ends) — one strongest
   attack, named in round one's Observe. `Output` comes right after
   `Shape` is settled, unless the attack reorders the walk.

| Slice | Question it answers |
|---|---|
| Shape (10k-ft) | context & why, PRFAQ demo, core mechanism (rules vs LLM vs hybrid), and what end action/artifact it produces |
| Output | what it emits: calls, verdict shapes, error codes, exits |
| Inputs | what it takes in: args, flags, env, config, files |
| Internals: data | shapes and schemas |
| Internals: state | lifecycle, stored vs derived |
| Internals: functions | edges, who does what |
| Internals: names | every variable and term, one line each |
| Internals: concepts | the coined vocabulary a newcomer must learn |
| Plan (nodes) | how to get there: node breakdown, dependency railway, parallel waves, per-node acceptance & test split (with optional zoom-in on any node the owner wants to inspect before settling) |

Domain experts supply slice definitions where one exists
(see Expert index).

## Round shape (one slice per round)

| Phase | Carries |
|---|---|
| Observe | the lay of the land, TL;DR first, cited from the artifact |
| Orient | the 2-4 things that matter, tensions, the turning question |
| Decide | exactly one detailed question: options + recommended answer. The owner calls it |
| Act | one edit to the working copy applying that one decision; “no edit” when the call was keep-as-is |
| IIUC | playback: settled, changed, still open |

```text
Observe -> Orient -> Decide -> Act -> IIUC -> next slice
              ^                                  |
              +---- owner corrects the read -----+
```

## Cases

| Situation | Move |
|---|---|
| Decide question still unanswered | stay on the slice |
| owner defers a question | record it under Deliberately open, with an owner; move on only when the owner says so |
| later decision reopens a settled slice | re-present that slice; the rest stay settled |
| a full pass completes | ask: another pass, or settle |
| owner says happy / settle | red-chair the settled design (below), then produce the exit pack, in order |
| owner adopts the copy | move the working copy over the original (`mv`, never a merge), set the lifecycle status the owner names; the old original survives in git history, and a recovery snapshot is saved first when the tooling offers one |

## Exit pack

| # | Item | Contents |
|---|---|---|
| 1 | Decision record | every settled decision, one line, before -> after, with its round |
| 2 | Inputs behind them | Observed (final lay of the land), Oriented (priorities) |
| 3 | Paths | original (untouched) + working copy |
| 4 | Deliberately open | deferred questions, each with an owner or an icebox path; plus icebox entries consulted at walk start |
| 5 | Final IIUC | the settled design in one read |
| 6 | Red chair of the settled design | the closing adversarial pass (below): findings with severity and evidence, including what the design survived |
| 7 | Proposed nodes | only when implementation follows; each node written per Nodes below — including the concern nodes the closing red chair owes (below) |

## Red chair at the ends

Two asymmetric passes, never a third in the middle (the
walk itself is the middle):

- **Opening attack (beginning, light).** Before round
  one, name the single strongest attack on the design
  as-is — how it most plausibly fails — in two or three
  sentences, read-only, no findings list. It seeds round
  one's Orient: if the attack is load-bearing, the walk
  starts at the slice it threatens instead of Output by
  rote. It produces no nodes; at the start, nothing
  is settled enough to owe proof.
- **Closing red chair (end, full).** When the owner says
  happy/settle, attack the *settled* design with the
  `red-chair` discipline (severity-ordered findings,
  evidence per claim, what it survived). Then every
  **critical or major** concern ends in exactly one of
  two places: settled by reopening the slice it attacks
  (the walk resumes; settle was premature), or appended
  as a **concern node** in the exit pack — an node
  in the Nodes shape whose acceptance proves the
  design, as settled, addresses the concern. Minor
  concerns go to Deliberately open. A critical/major
  concern with neither a reopened slice nor an node
  blocks the exit pack: do not present a clean settle
  over it. The closing red chair always runs `quest`
  step 7's two fixed passes: the **constraints pass**
  against `CONSTRAINTS.md` (an addition outside it is
  at least major, and only the owner's words settle
  it) and the **common-sense pass** against
  `CONTEXT.md`.

## Nodes

Proposed nodes, and any node walked during a pass, are
presented in this shape, in this order:

```text
TL;DR -> demo -> diagram (ascii) -> pseudocode (python)
      -> tables -> acceptance test (goal block) -> prose -> tests
prose = context, why, how we got here, edge cases
code  = what we're gonna do
```

| Part | Carries |
|---|---|
| Demo | up front: one worked trace, labeled `observed` or `design trace` |

Worked example (miniature — voice and scale, not a template):

```text
## Demo (design trace)
conductor: mint link for node N, edge handoff -> bp3link_7f3a…
child: claim bp3link_7f3a… -> claimed {run_id, session_id, desk}
child: build -> bp3 e handoff --commit 4fc0cc4 -> {state: handed_off}
second claim of bp3link_7f3a… -> E_LINK_SPENT {first_claim: …}
```
| ASCII diagram | the flow at a glance: inputs, outputs, where it can stop |
| Python pseudocode | the mechanism in one readable pass |
| Tables | intent, lane, output, acceptance that fails today, depends-on; cases and gates |
| Acceptance test | one goal-shaped block: `objective`, `prove by`, `done when` (the exact observation) |
| Prose | context, why the node exists, how we got here, edge cases |
| Tests | the test split, both kinds proposed: **known cases** (named examples — boundaries, goldens, exact shapes; fast, legible when red) and **property-based** (law + generator; breadth). Either kind may be omitted only as a stated one-line decision; silence is not a decision |

An node whose acceptance passes today gets sent back: a check
that cannot fail is a hope, and hopes do not gate builds. An
node whose tests never state both kinds — or a justified
omission of one — is unfinished the same way. An
node with no demo and no runnable goal block is unfinished
spec. The design file itself gets the same treatment at its
scale: a Demos section up front, traces honestly labeled.

## Quest-level functional tests

When the artifact is a whole quest (or another multi-node
design), add a closing functional pass after the per-node
tests. These are not larger unit tests: they drive the
public interfaces end to end — CLI, workflow, files, git
artifacts — and prove the nodes compose into the quest's
promise. Put the cases at the end of the working copy,
after all node sections. Each case names its starting
state, the actions taken, the exact observable result,
and its evidence label.

Cover, where they apply: the happy path across the whole
quest; one refusal or failure path with state unchanged;
the human gate and recovery from it; crash or restart with
state reconstructed from the record; and consistency
across surfaces (JSON verdict, ledger, files, human view).

Separate true end-to-end cases (real harness, real
processes) from functional fixtures (same public path in a
fake repo) and label which is which. A quest whose
functional cases only restate per-node tests is unfinished.
A quest proposing only design traces must say so plainly.

## Rules

| Rule | Why it exists |
|---|---|
| copy first; name both paths in round one | the original never takes an edit |
| one question per round | a round with no Decide produced nothing |
| owner is the gate | the loop ends on the owner's word |
| decisions recorded in the owner's words | editorials belong in Orient, before the call |
| stateless skill | the working copy + transcript carry all memory |

Terms sync with code and data: during names and concepts rounds,
check every term against the identifiers it becomes (CLI verbs
and flags, states, ledger fields, files, branches, types,
variants). Code or data already has a spelling -> the design
adopts it. Owner renames -> the Act applies the new spelling
across the working copy and records the matching code/data
rename as owed in the same change. Two spellings for one concept
means the decision is still open.

## Expert index

| Domain | Lens |
|---|---|
| CLI designs | `expert-cli` (calls/verdicts/error codes; args/flags/env; data/state/fn/names/concepts) |

New experts enter through the add-skill gates, one at a time,
and join this index as a named edit.
