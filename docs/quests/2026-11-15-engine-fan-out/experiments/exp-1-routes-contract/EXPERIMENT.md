---
date: 2026-11-15
quest: ../../QUEST.md
exp: 1
status: proposed
---

# Exp 1 — Routes contract: `exp_routes.json`, typed and validated

## TL;DR

The groupwise plan becomes a typed artifact: `exp_routes.json`
in the quest folder, read by the engine **from the quest
branch tip** (never the working tree), validated on every
read, with the open stage derived — never stored — from
member exp states. Schema: `{quest, status:
proposed|approved, stages: [{stage, exps: [{exp, paths:
[...]}]}]}`. Validation refuses, as verdicts: unknown or
duplicated exp, missing exp, unapproved file at dispatch
time, and overlapping `paths` within a multi-member stage
(a stage with >1 member and any missing `paths` is
refused outright). `bp3 q r <quest>` gains `routes:
{stage, members, stage_state}` where `stage_state` is a
pure function of member states (`open`, `closed`,
`parked`). No parallelism in this exp: serial dispatch
against a valid routes file behaves exactly as today —
the contract must be checkable before anything runs
concurrently.

Red-chair fixes baked in (2026-11-15): routes read from
branch tip (working-tree reads make semantics depend on
the conductor's checkout); declared `paths` in the file
(markdown `Output` prose is not machine-checkable);
stage state derived, never stored (a stored stage state
desyncs on the resume path).

## Demo (design trace)

```text
$ ./bin/bp3 q r some-quest
{"ok":true, ..., "routes":{"stage":2,"members":["exp-3"],
  "stage_state":"open"}, ...}

$ ./bin/bp3 q r bad-quest        (routes names exp-9 twice, paths overlap in stage 1)
{"ok":false,"error":{"code":"E_INVALID_ROUTES",
  "facts":{"problems":["duplicate exp: exp-9","path overlap in stage 1: src/quest/main.ml"]}}, ...}
```

Today (observed): no `routes` anywhere in `src/quest/`,
the induct skills, or the quest skill; `bp3 q r` has no
stage concept.

## Diagram

```text
exp_routes.json (quest branch tip) ─► parse + validate ─► problems? ─► E_INVALID_ROUTES (all named)
                                            │ clean
                                            ▼
                              derive stage from exp states ─► q r verdict gains routes{...}
                              dispatch (Exp 2) refuses unless status == approved
```

## Pseudocode

```python
def load_routes(quest):
    text = git_show(quest_branch(quest), quest_dir(quest) + "/exp_routes.json")
    if text is None: return None                      # absent = today's serial railway
    r = parse_json(text)                              # malformed -> E_INVALID_ROUTES
    problems = (unknown_exps(r) + duplicate_exps(r)
              + [overlap(p) for stage in r.stages for p in path_pairs(stage)]
              + (["multi-member stage without paths"] if any(len(s.exps) > 1 and missing_paths(s))))
    return (r, problems)

def stage_state(members):                             # derived, never stored
    if any(m.state == "blocked" for m in members): return "parked"
    if all(m.state in ("landed", "deleted") for m in members): return "closed"
    return "open"
```

## Tables

| Field | Value |
|---|---|
| Intent | grouping becomes a machine-checkable contract before any concurrency exists |
| Lane | standard |
| Output | routes load/validate in `src/quest/store.ml`; `routes` verdict field via `src/quest/render.ml` / dispatch; fixtures in `test/q.sh` |
| Acceptance | cases below; headline cases fail today (observed) |
| Depends on | none |

| Case | Expected after |
|---|---|
| no `exp_routes.json` | `bp3 q r` byte-identical to today; no `routes` field, no error |
| valid approved routes | verdict carries `routes{stage, members, stage_state}` matching member states |
| duplicate / unknown / missing exp | `E_INVALID_ROUTES` naming every problem in one verdict |
| overlapping `paths` in a stage | refusal naming the overlapping path and stage |
| multi-member stage, missing `paths` | refusal (single-member stages exempt) |
| malformed JSON | `E_INVALID_ROUTES`, never a crash |
| `status: proposed` | reads succeed and show the stage; dispatch-shaped verbs (`c`, `u`, `d` under a routes quest) refuse with the approval named as the missing act |
| working-tree routes differ from branch tip | engine follows the branch tip (observed by editing the file uncommitted mid-test) |
| member blocked / all landed | `stage_state` is `parked` / `closed` with no stored stage anywhere |

## Acceptance test (goal block)

- **Objective:** routes are typed, validated, and read
  back truthfully — with zero change to serial behavior.
- **Prove by:** the traced verdicts against scratch
  quests with planted routes files (valid, duplicate,
  overlapping, malformed, unapproved, working-tree-only);
  byte-diff of `bp3 q r` on a routes-less quest vs today;
  `make check` green.
- **Done when:** every refusal names its problems, the
  no-routes diff is empty, and stage derivation matches
  member states in all three states.

## Prose

Context: the owner's railway refinement — linear stages,
parallel groups — needs its plan somewhere checkable.
Why branch tip: quest state already lives there
(`QUEST.md` is read from HEAD at quest create), and the
conductor may sit in any of several worktrees; a plan
whose meaning changes with the reader's cwd is not a
plan. Why `paths` ride in routes instead of being parsed
from EXPERIMENT.md tables: prose parsing would make the
engine's most safety-relevant check depend on markdown
formatting habits. Exp 3's framing writes both from the
same source so they cannot drift silently. Why JSON, not
YAML like `plans/`: verdicts are JSON, `jq` is already
the test tool, and Pi reads JSON natively — the contract
is deliberately the cheapest format both engines speak.

## Tests

unit: none (parser/validator is fixture-sized) ·
fixtures: all refusal/derivation cases above in
`test/q.sh` scratch quests · demos: the traced verdicts
on a scratch quest at review
