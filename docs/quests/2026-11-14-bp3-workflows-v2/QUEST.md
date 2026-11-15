---
status: landed
home_repo: bp3
date: 2026-11-14
---

# bp3-workflows-v2: one workflow per state transition

TL;DR
The fat bootstrap workflow splits into step functions:
`induct-exp` builds only, a new `induct-grade` judges
only, the `induct` conductor owns the loop, and every step
Runs from a prepared worktree desk. Promoted from
the workflows-v2 icebox entry (promoted with this quest and deleted at promotion, per owner rule 2026-11-15; preserved in git history);
promotion per the `quest` skill — transcription, not
adoption. Depends on [bp3-worktrees](../2026-11-14-bp3-worktrees/QUEST.md)
for the desk verbs.

ELI5
One worker used to build the thing, grade it, and stamp
it, all in one long shift. Now the builder builds, a
separate judge grades against the checklist, the foreman
decides what's next, and everybody works at their own
desk so nobody's papers blow into anyone else's pile.

## Terms

| Term | One line |
|---|---|
| Step function | a workflow that reads state once, does exactly one stage, returns; owns nothing between invocations |
| Conductor | the `induct` skill in the main session: loops `bp3 q r` → dispatch step → re-read |
| Grade | judge-only verdict work on a bound commit: evidence audit, review, check; never edits |
| Evidence audit | one row per acceptance case with its observed artifact or `missing`; missing required evidence = not pass |
| Grade return | what `induct-grade` hands the conductor (owner, Round 1): the outcome word **plus the evidence matrix** — `{case, evidence, verdict}` per case, acceptance and adherence rows alike — in the workflow return and in the grade Run's `notes.md`. The conductor quotes it verbatim; nothing is re-judged downstream |
| Step inputs | every step workflow takes `{quest, exp, ts, harness, model}` from the conductor; `induct-grade` additionally takes `commit` (owner, Round 2): the conductor reads state and hands over exactly the commit to judge. Staleness stays the FSM's problem (`E_COMMIT_MISMATCH`), not the grade's |
| Matrix row | `{case, evidence: {kind: file\|command\|ledger\|grep, ref, quote}, verdict: pass\|fail\|missing}` (owner, Round 3). `missing` is first-class: a row without typed evidence cannot be `pass`, and a free-string evidence field is not a row |
| Grade replay | re-dispatching `induct-grade` on the same commit is always safe (owner, Round 4): the audit is read-only, re-cast verdicts bind the same commit, and the FSM absorbing or refusing them is information either way. No conductor-side attempt bookkeeping |
| Matrix rows, two families | the matrix carries **acceptance rows** (the exp's cases) and **adherence rows** (owner, Round 4): did the build Run follow the workflow contract — edge called by the child directly, env preset on the first command, clean commit, tape + notes present, no hand-edited state, worktree exited — or did it skip, substitute, or stay silent? Adherence is not a separate audit layer; it is rows, with the same typed evidence and `pass\|fail\|missing` verdicts |
| Edge guard | the adherence checker inside `bp3 q u` itself (owner, Rounds 5+8, simplified): before applying an edge for a Run, the binary verifies that Run's adherence rows (run folder + tape present, worktree state sane, evidence the verdict binds to) and refuses with the failing rows when incomplete. Two placements only: the guard makes cheating fail at the state move; the grade re-derives the same rows and makes everything visible in the matrix. A `Stop` hook placement was considered and dropped entirely (owner, 2026-11-15) — guards live in `bp3 q u` plus grade reporting, nowhere else |
| `E_ADHERENCE` | the edge guard's refusal code (owner, Round 6): one family code for "the workflow did not follow its contract," failing rows in `facts`, guidance naming the first fix. Per-row codes (`E_DIRTY_TREE`, …) still exist underneath; `E_ADHERENCE` is what a conductor greps for |
| Desk | a prepared worktree (`bp3 worktree`, bp3-worktrees quest) |

## Demos

### Observed — the monolith (MVP, 2026-11-13/14)

```text
induct-exp one invocation: author 66 tool calls -> review -> check -> land
usage_recorded per Run (exp-7 c2): 6.85M / 1.58M / 537K / 426K input tokens
grade cannot rerun without re-entering the implementation workflow
```

### Observed — the pieces already exist (2026-11-14)

Worktree verbs, live in this repo (DEMO-show run):

```text
$ ./bin/bp3 worktree prepare <q> <e> --run DEMO-show
{"ok":true,"path":".bp3/worktrees/<q>/<e>/DEMO-show","ref":"bp3/exp/<q>/<e>", ...}
$ (stray edit) ./bin/bp3 worktree release --run DEMO-show
{"ok":false,"error":{"code":"E_DIRTY_TREE","facts":{"changed_count":1},
 "guidance":"Worktree is dirty; commit the work or remove with --force."}}
$ (edit reverted) release -> {"ok":true,"released":true}; list -> []
```

Hook facts, live (exp-7 of the MVP quest): ledgers carry
`run_started` / `usage_recorded` / `run_settled` written
by `bp3 q hooks` — the adherence checker's raw material
already flows.

### Design traces — v2 (nothing here has run yet)

**Grade with a typed matrix:**

```text
bp3 q r -> submitted (commit abc1234)
induct-grade {quest, exp, ts, harness, model, commit: abc1234}
  audit child -> matrix:
    {case:"acceptance: dirty desk refuses release", verdict:"pass",
     evidence:{kind:"command", ref:"test/worktree.sh", quote:"worktree tests: ok"}}
    {case:"adherence: submit edge called by the child", verdict:"pass",
     evidence:{kind:"ledger", ref:"submit line", quote:"run_id matches, muse-code"}}
    {case:"adherence: worktree exited at settle", verdict:"missing",
     evidence:{kind:"command", ref:"bp3 worktree list", quote:"1 still open"}}
  reviewer || checker (parallel, worktrees detached at abc1234)
-> needs_fix (missing row named) — conductor quotes the matrix verbatim
```

**The cheat, caught mechanically:**

```text
child returns a verdict JSON but never calls bp3 q u
  -> conductor re-reads state: nothing moved; the Run is wasted, never believed
child calls bp3 q u submit with no tape / dirty worktree
  -> {"ok":false,"error":{"code":"E_ADHERENCE", facts:{rows:[...]}, guidance:"..."}}
```

**Grade replay:** conductor re-dispatches `induct-grade`
on the same commit after a killed checker — audit
re-runs read-only, verdicts re-cast against the same
commit, same matrix out. No attempt bookkeeping.

## Goal and why

The monolith worked — it dogfooded a quest to landed —
but it concentrates trust: one driver builds and judges,
its JS re-derives the FSM that `bp3 q` already owns, and
a grade cannot be rerun against the same commit without
re-entering the whole machine. Exp 4/6 showed where that
leads: motion mistaken for proof. Splitting by state
transition makes each piece small, separately rerunnable,
and honest about what it cannot prove.

## Success picture

A quest driven end to end by the conductor with the split
workflows: build Runs and grade Runs as distinct ledger
citizens, a grade rerun on an unchanged commit producing
the same verdict without touching implementation, graders
in detached desks, and the monolith deleted.

**Landed 2026-11-15 (owner gate).** All five exps landed
through `bp3 q` (exp-1 `b415f4a3`, exp-2 `546a4b3f` c3,
exp-3 `e5e09bea` c3, exp-4 `caf880e1`, owner-ruled
follow-up exp-5 `4460ea7c` c2); rollup `landed`, inbox
empty, `bp3 worktree list` empty, `make check` green.
The live drive and token comparison rode the toy quest
`2026-11-15-toy-conductor-drive` (also landed).

## Scope

| In | Out |
|---|---|
| `induct-grade` workflow (new), `induct-exp` slimmed to build-only, `induct` conductor loop | quest-level E2E (stays in the landing pass) |
| desk adoption in every step (via bp3-worktrees) | changing `bp3 q` or the FSM |
| skill changes as their own exp (Exp 3, per /quest step 6.6) | folding skill text into the workflow-code exps |

## Human touchpoints

Quest approval (this file); blocked-exps inbox as today;
landing gate. Grade verdicts remain child-cast edges
bound to exact commits, as today.

## Exps

### Exp 1 — [induct-grade](experiments/exp-1-induct-grade/EXPERIMENT.md)
New judge-only workflow: evidence audit, then review +
check in parallel on the bound commit. Depends on: none
(consumes today's `submitted` state). Lane: standard.

### Exp 2 — [induct-exp slimmed](experiments/exp-2-induct-exp-slim/EXPERIMENT.md)
`induct-exp` keeps only author + submit; grading stages
deleted; conductor dispatches by state instead.
Depends on: Exp 1 (grade must exist before the monolith
stops grading). Lane: standard.

### Exp 3 — [Conductor](experiments/exp-3-conductor/EXPERIMENT.md)
Skill-change exp: `induct` SKILL.md rewritten as the
state loop over step functions (build / grade / land /
inbox). Includes the QoL alias (owner, Round 2):
`induct-quest`, a second name meaning exactly `/induct`
— one canonical skill body, the alias a thin pointer,
never a forked copy that can drift. Depends on:
Exp 1 + 2. Lane: standard.

### Exp 4 — [Desks](experiments/exp-4-desks/EXPERIMENT.md)
Every step Runs from a prepared `bp3 worktree` desk
(author on branch, graders detached). Depends on: Exp 2
+ bp3-worktrees Exp 1. Lane: standard.

## Scorecard

| Field | Value |
|---|---|
| Wall time / context tokens | measured 2026-11-15 on the same toy (one hello file, toy quest `2026-11-15-toy-conductor-drive`): step dispatches (`exp-1-hello`: induct-exp + induct-grade + quest-land, separate workflows) 12,523,838 input / 108,592 output tokens, 17 LLM calls, 4 registered Runs vs monolith (`exp-2-hello-monolith`, monolith recovered from `31f82b2`, one workflow) 16,417,835 input / 157,726 output, 33 calls, 4 Runs — the split is cheaper on this toy even before caching effects; per-Run `usage_recorded` sums from `.git/bp3-run-registry.json` |
| Exp 2 file-weight proxy (2026-11-15) | monolith `induct-exp.js` 296 lines / 12349 B at `b415f4a` -> slim `induct-exp.js` 213 lines / 8039 B plus `quest-land.js` 197 lines / 7320 B; the build step alone sheds ~35% of its bytes. The live `usage_recorded` per-Run token comparison on a re-driven toy exp is NOT gated by Exp 2 — explicitly deferred to Exp 3 (cycle-2 amendment after cycle-1 review); the proxy above is all Exp 2 records. |
| Human-active minutes | approval + inbox + landing |

## Risks and red chair

| Attack | What it changed |
|---|---|
| Split is ceremony: same children, more files | grade gets a different contract (evidence audit, missing = not pass), not just a new folder; without that, this quest is pointless and should not start |
| Conductor loop in a skill = prose FSM duplicating `bp3 q` | conductor only dispatches on state `bp3 q` reports; it decides nothing about legality |
| More invocations, more overhead | measured in Scorecard against the monolith on the same toy exp; if overhead dominates, the split is revisited at Exp 2's gate |
| Two workflows drift apart in run/tape conventions | run-id, env preset, and tape derivation stay shared and pinned by the same contract test family |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Land: mini-workflow, or single conductor-spawned child? | human, at Exp 2 |
| 2 | ~~Grade on a different model~~ — not this quest (owner, 2026-11-15): TODO frozen in [grade-model-routing icebox](../../icebox/2026-11-15-grade-model-routing.md) | icebox |
