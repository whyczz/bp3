---
date: 2026-11-15
goal: ../QUEST.md
exp: followup.4
status: proposed
---

# followup.4 - bind-resolution: which tape is the Run's own?

## TL;DR

followup.3 landed the bind verb and the fold honor,
but its launcher resolution — `find-tape --run-id` —
refuses live: `E_AMBIGUOUS` with four candidate
tapes for one Run (dogfood.1 cycle 5, refused bind
in the workflow result). Every workflow child's
brief carries the run-id string, so sibling sessions
(init, resolve) and the conductor session all
"reference" the Run. Only one tape is the Run's
own: the one carrying the Run's own engine-fsm-edge invocation
— `BP3_RUN_ID=<R>` bound to its `bp3 q … u <exp>
<edge>` call. The init tape binds the id to
`record-init`, the resolve tape to `find-tape`;
neither ever invokes the Run's engine-fsm-edge. Resolve by
that, uniquely, or refuse typed.

## Demo (design trace)

```text
find-tape --run-id R      (4 candidates reference R)
  -> keep tapes carrying R's own engine-fsm-edge invocation
  -> exactly one: the author's session tape
  -> bind-tape writes the pointer; supervisor derives finished
two engine-fsm-edge tapes -> E_AMBIGUOUS (never a guess)
```

## Diagram

```text
candidates ──► engine-fsm-edge filter ──► 1 tape ──► bind ──► fold
                    │
                    └─ 0 or ≥2 ──► E_AMBIGUOUS (typed)
```

## Pseudocode

```python
def resolve(run):  # establish the pointer, once
    cands = tapes_referencing(run.id)
    own = [t for t in cands if carries_own_engine_fsm_edge(t, run)]
    viable = [t for t in own if session_start(t) >= run.init_ts]
    if not viable or not unique_earliest(viable): refuse E_AMBIGUOUS
    return earliest(viable)

def bind(run, tape):  # 1 tape <> 1 run-id, pinned in local state
    if bound(run.id) or owner_of(tape): refuse typed
    append_binding_row(run.id, tape)  # fold reads only this, forever
```

| Field | Value |
|---|---|
| Intent | make `find-tape`/`watch` resolution (and the launcher bind step) succeed uniquely for live workflow Runs |
| Lane | standard |
| Output | own engine-fsm-edge resolution rule in the shared tape resolution; bind succeeds live |
| Depends on | followup.3 (bind-tape, fold honor); found at dogfood.1 cycle 5 |

## Acceptance (fails today: bind resolution refuses E_AMBIGUOUS live)

| Case | Expected |
|---|---|
| sibling tapes reference the Run | init/resolve/conductor tapes mentioning the run-id do not resolve; the tape carrying the Run's own engine-fsm-edge invocation does |
| still not unique | two tapes carrying the Run's own engine-fsm-edge invocation (or none) → `E_AMBIGUOUS`, typed, never a guessed pick |
| established by start order | among own-engine-fsm-edge carriers, the earliest session started at-or-after the Run's InitRecord is the Run's tape; a tie or none → `E_AMBIGUOUS` |
| one-to-one, pinned | 1 tape <> 1 run-id, kept as local state (binding rows): once a run-id is bound, that pointer is the only one the fold reads; a tape already bound to another run-id, or a second different tape for the same run-id, refuses typed — never a silent rebind |
| live bind | a fresh induct-exp submit Run binds post-author (no refusal in the workflow result) and the supervisor derives `finished` for it |
| resolution is shared | `find-tape` and `watch` apply the same rule; a tape named by an InitRecord or a binding row still wins over any scan |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** resolution names the Run's own tape
  or refuses — mechanically, on live session stores.
- **Prove by:** harness fixtures shaped like the
  real sibling set (an init tape, a resolve tape, a
  quoting conductor tape, the author's own tape),
  plus the workflow bind exercised end to end.
- **Done when:** every Acceptance case resolves as
  named and `make check` is green.

## Context

Live evidence (dogfood.1 c5): candidates
`605ffc91` (author: 7 submit invocations, 0
record-init), `60600191` (resolve: 7 find-tape, 0
submit), `605ffb91` (init: 5 record-init, 0
submit), conductor `session.jsonl` (quotes all).
The own engine-fsm-edge signal separates them without any
child-reported identity. The edge name is the
run-id's second segment and the exp comes from the
Run's InitRecord, so the rule needs no new inputs.

## Tests

Known cases: Acceptance table; env-set run-id
stamped by bp3 into the submit verdict and ledger
line. Property-based: resolution never returns a
tape that does not carry the Run's own engine-fsm-edge
invocation when it had to choose among several;
when the InitRecord or a binding names the tape,
no scan result can override it.
