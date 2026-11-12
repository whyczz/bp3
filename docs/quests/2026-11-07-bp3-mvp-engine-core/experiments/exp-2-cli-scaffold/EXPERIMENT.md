---
date: 2026-11-07
quest: ../QUEST.md
exp: 2
status: proposed
---

# Exp 2 — CLI scaffold: u, discover, CRUD

## TL;DR

The `bp3 q` CLI: hierarchical doors, one JSON verdict shape,
named error codes with structured facts and guidance, strict
argv, env-only identity, and the blocked inbox. The update is
the only writer of FSM state.

Status: **proposed, not implemented or verified.**

## Demo (design trace — nothing here has run yet)

```text
$ bp3 q demo c parser-fix
{"ok":true,"quest":"demo","state":"proposed"}

$ BP3_HARNESS=muse-code BP3_MODEL=muse-wonder-1.0 \
  bp3 q demo u parser-fix submit --commit abc1234 --reason "parser: handle empty input"
{"ok":true,"state":"submitted","commit":"abc1234","cycle":1,"legal_edges":["review","check","block"]}

$ bp3 q demo u parser-fix land --reason "ship it"
{"ok":false,"error":{"code":"E_ILLEGAL_EDGE","facts":{"state":"submitted",
 "edge":"land","legal_edges":["review","check","block"]},
 "guidance":"This commit is still collecting verdicts. Review or check it, or block the exp."}}
```

```text
caller (agent / engine / human)
   |
   v
parse argv -> validate+resolve -> judge (FSM table) -> CAS commit -> verdict
   |               |                    |
 E_USAGE      E_NOT_FOUND          refusal -> JSON only
                                   accepted -> ledger line + 1 commit
reads: fold ledger at branch tip -> verdict (+ blocked inbox)
```

```python
def bp3_q(argv):
    call = parse_strict(argv)            # unknown/dup/stray -> E_USAGE
    ctx = resolve(call)                  # quest, exp, refs, plans, exp_type
    who = identity(env BP3_HARNESS, BP3_MODEL)   # missing -> unknown + warning
    result = judge(ctx.state, call.edge, call.flags, guards)
    if result.refused:
        return verdict(error=result.code, facts=result.facts,
                       guidance=result.guidance)        # never ledgered
    append_cas(ctx.exp_branch, ledger_line(result, who, bp3_version))
    return verdict(read ctx.exp)         # write returns the read after it
```

## Tables

| Field | Value |
|---|---|
| Intent | Name the seam: the only writer of FSM state |
| Lane | standard |
| Output | The CLI below, with one JSON verdict shape (`--format table` for humans, same facts) |
| Depends on | none (Exp 1 baseline killed by the owner) |

Call surface:

| Call | Shape |
|---|---|
| Quest door | `bp3 quest` / `bp3 q`, verbs `c\|r\|d` (`create\|read\|delete`; `r` retires `get`) |
| Exp door | `bp3 q <quest> c\|r\|u\|d <exp> [edge] [flags]`; only `u` takes an edge |
| Quest create | `c <quest> [--type <quest_type>] [--depends-on <a,b>]`, born `proposed`; no `--engine` (engine is per-Run) |
| Exp create | `bp3 q <quest> c <exp> [--type <exp_type>]` |
| Quest delete | `d <quest> --reason "..."` — terminal ledger move, removes nothing |

Inputs and identity:

| Rule | Value |
|---|---|
| Write flags | `--reason` on every write; `--verdict` on review/check, `--commit` on submit, `--target` on land |
| Identity flags | none. Env-only: `BP3_HARNESS` (closed enum), `BP3_MODEL`, set per Run by launcher or installed-app hook |
| Ledger identity | `harness`, `model` (`none` for human, `unknown` when unset), `bp3_version` stamped by the binary |
| Missing identity | record `unknown`, verdict carries `W_IDENTITY_UNKNOWN`, move proceeds |
| Invalid identity | fail fast |
| Env otherwise | session plumbing only (`BP3_ROOT`, `BP3_UPDATE_BIN`; today `BP3_INVOKE_BIN`) |

Errors worth a code (one code per remedy, never per state/edge pair):

| Code | Remedy it implies |
|---|---|
| `E_ILLEGAL_EDGE` | pick from `legal_edges` in the facts |
| `E_COMMIT_MISMATCH` | re-issue against the exact current commit |
| `E_DIRTY_TREE` | clean the tree, retry |
| `E_STALE_WORLD` | re-read, re-judge, retry (pointer race, never a human) |
| `E_HUMAN_REQUIRED` | ask the human (on `resume`, delete-from-blocked) |

## Acceptance (fails today: no `bp3 q` CLI exists)

| Case | Expected |
|---|---|
| read and write verdicts | same JSON shape; table adds no facts |
| refusal (`land` from `todo`) | `E_ILLEGAL_EDGE` with state/edge/legal_edges; nothing ledgered |
| duplicate flag, unknown flag, stray positional | usage error before any ledger write |
| every verb, both spellings | `c`/`create`, `r`/`read`, `u`/`update`, `d`/`delete` behave identically, all tested |
| identity unset / invalid | `unknown` + warning / fail fast |
| exp enters `blocked` | verdict flags `human_action_required`; quest reads return the blocked inbox in JSON and table |
| notify hook | MVP stub receives the blocked verdict JSON; binary sends no external notifications |

## Acceptance test (goal block)

- **Objective:** build the `bp3 q` CLI scaffold specified above,
  with `bp3 q <quest> u <exp>` as the only writer of FSM state.
- **Prove by:** the fixture suite (successor to `test/invoke.sh`)
  covering every case in the Acceptance table: verdict shapes,
  refusal codes/facts/guidance, strict argv, both verb spellings,
  identity resolution, blocked inbox.
- **Done when:** the fixture suite is green end to end, and a
  hand-run demo (create quest, create exp, submit, one refused
  edge) prints verdicts matching the Demo section's shapes.

## Context

The callers are LLMs, and their failure mode is the confident
typo: a flag that almost spells the real one, an edge fired
from the wrong state. A CLI that guesses in those moments
corrupts state politely and calls it helpful. So the call
passes a strict door — parse, validate/resolve, judge,
finalize — and anything malformed dies before a ledger write.
Identity rides env for the same reason: the harness knows who
it is; an agent made to type its own name on every call will
eventually type a wrong one, and parallel subagents sharing an
ambient fallback will misattribute each other. Judgment, by
contrast, changes per call, so judgment stays in flags.

Worktree prepare/release is engine-internal choreography,
kept out of the CLI on purpose: the binary tells, judges, and
finalizes; helper shell scripts for worktrees are a separate
post-MVP quest. Executor launching across harnesses builds on
this scaffold in later exps, outside it.

Edge cases: a write against a moved tip loses the CAS and
re-judges from the new tip — a machine retry, never an
escalation. A malformed ledger, plan, or exp_type stops the
call with a named code; the tool invents no fields and repairs
nothing, so corruption gets a human. Quest folders that
predate this CLI are adopted, not converted by hand. Pi engine
extraction was removed from this exp and frozen in the
[pi-engine icebox entry](../../../../icebox/2026-11-11-pi-engine.md).
