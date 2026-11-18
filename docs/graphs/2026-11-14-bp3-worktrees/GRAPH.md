---
status: landed
home_repo: bp3
date: 2026-11-14
---

# bp3-worktrees: one worktree per Run

TL;DR
Every workflow child gets its own git worktree — the author
on the exp branch, graders detached at the bound commit —
prepared and released through bp3 itself (`bp3 worktree
prepare|release`), so the conductor's tree never moves and
parallel children never share a checkout. This is the
prepare/release helper deferred during the MVP storage
design, now explicit.

ELI5
Today every worker shares one worktree: children check out
branches under the main session, parallel graders read the
same files, and the conductor occasionally finds its own
commits on a child's branch. This quest gives each worker
its own worktree, labeled by the tool itself, and a cleanup
that refuses to throw away unfinished work.

## Terms

| Term | One line |
|---|---|
| Worktree | a `git worktree` checkout of this repo at a branch (author) or detached commit (graders); machine-local, never ledger state |
| Run ID | the primary key for a worktree's lifecycle and bookkeeping. Quest and exp are creation context and path namespace, not competing lifecycle keys |
| Util layer | low-level worktree primitives: derive the worktree path, create/remove a worktree, and inspect its ref and dirty state. No registry and no workflow policy |
| Bookkeeping layer | the machine-local worktree registry keyed by `run_id`: creation context, actual path (including overrides), lifecycle, `check`, `exit`, `list`, and staleness |
| Conventions layer | how Runs and workflows use worktrees: when each child prepares one, what kind it gets, when it exits, and what the conductor does with stale or dirty worktrees |
| One file per key | machine-local bookkeeping stores one file per primary key (`.bp3/desks/<run_id>.json`, created exclusively, deleted on release) — never one shared file rewritten by load-modify-save, which loses parallel writers' records |
| Run worktree | `.bp3/worktrees/<quest>/<exp>/<run-id>/` — the default physical path for the worktree owned by that Run ID. (Name settled Round 6: "desk" was coined for this and killed — one concept, one word, and the word is git's: *worktree* everywhere, CLI, docs, and prompts) |

## Demos

### Observed — the wart (MVP iteration, 2026-11-13/14)

```text
workflow launch receipts: every child "Subagent workspace: shared"
two main-session commits landed on bp3/exp/toy-drive/parser-fix
  (a child had it checked out in the shared tree)
branch switch blocked mid-Exp-7 by a child's appended tape.log
```

### Design traces — every scenario, played through (nothing here has run yet)

**S1 · Author, happy path**

```text
$ BP3_RUN_ID=R1 ./bin/bp3 worktree prepare <q> <e> --run R1
{"ok":true,"path":".bp3/worktrees/<q>/<e>/R1","ref":"bp3/exp/<q>/<e>"}
... work, git commit ... (conductor's branch never moves)
$ ./bin/bp3 worktree exit        # inside the worktree, clean after commit
{"ok":true,"released":true,"conductor_path":"<repo root>"}
```

**S2 · Child dies, replacement resumes (idempotent prepare)**

```text
$ ./bin/bp3 worktree prepare <q> <e> --run R1
{"ok":true,"existing":true,"path":".bp3/worktrees/<q>/<e>/R1", ...}
# same worktree, same uncommitted context, no recovery branch in the prompt
```

**S3 · Two graders, one bound commit, in parallel**

```text
$ ./bin/bp3 worktree prepare <q> <e> --run R2 --commit a09109c3
$ ./bin/bp3 worktree prepare <q> <e> --run R3 --commit a09109c3
# two detached worktrees, same sha; _build/ and tests never collide
both judge -> exit -> list shows neither
```

**S4 · Dirty worktree refuses to die**

```text
... stray edit, no commit ...
$ ./bin/bp3 worktree exit
{"ok":false,"code":"E_DIRTY_TREE","guidance":"commit, checkpoint, or release --force"}
# worktree and edit intact; --force exists but must be named explicitly
```

**S5 · Killed Run, stale worktree, quest sweep**

```text
(child killed mid-Run; nobody calls exit)
$ ./bin/bp3 worktree list
{"worktrees":[{"run_id":"R4","dirty":true,"stale_s":3600, ...}]}
# conductor: dirty -> preserve + surface path in the human inbox (never swept)
# clean stragglers -> released by the landing sweep; dirty blocks landing
```

**S6 · Path override**

```text
$ ./bin/bp3 worktree prepare <q> <e> --run R5 --path /scratch/wt
{"ok":true,"path":"/scratch/wt", ...}
$ ./bin/bp3 worktree check --run R5     # Run ID still finds it; recorded, not derived
{"ok":true,"dirty":false,"ref":"bp3/exp/<q>/<e>","stale_s":3}
```

**S7 · Quest lands, zero worktrees**

```text
$ ./bin/bp3 worktree list --quest <q>   # during the landing ceremony
{"worktrees":[]}                        # after the sweep; nonzero clean = leak, dirty = blocker
```

**S8 · Another engine, same verbs (oh-my-pi)**

```text
(pi pane agent)  $ ./bin/bp3 worktree prepare <q> <e> --run R6
                 ... same verdicts, same lifecycle; no Muse surface involved
```

## Goal and why

The engine's children are parallel and disposable; the
shared checkout is neither. State already lives in branch
refs via plumbing, so nothing except habit ties a child to
the conductor's tree. Owning prepare/release in bp3 (not
ad-hoc shell in prompts, not a Muse-only workflow flag)
keeps the path derivation in one place, identical for
every engine, with JSON verdicts LLM children can act on.

Settled shape (owner, 2026-11-14): `bp3 worktree`
verbs on the `bin/bp3` surface, implemented in the OCaml
binary the wrapper already dispatches to — so verdicts,
error codes, and guidance come from the one place that
owns them, and path derivation is unit-testable. Not a
`bp3 q` state verb: worktrees are machine-local like the
hook registry, never ledgered, and the binary's worktree
mode writes only `.bp3/` and git worktrees. The Muse
workflow `isolation` flag stays an alternative for hosts
that prefer it; bp3 does not depend on it.

Layering (owner, Round 3):

| Layer | Owns | Does not own |
|---|---|---|
| Util | path derivation, `git worktree` create/remove, ref and dirty inspection | registry, staleness policy, workflow behavior |
| Bookkeeping | one worktree record per `run_id`, actual path and override, lifecycle, `check`, `exit`, `list`, staleness | how workflows choose or use worktrees |
| Conventions | worktree kind per child, enter/exit discipline, release timing, conductor handling of dirty/stale worktrees | git mechanics or registry storage |

Five public verbs compose those layers: `prepare`
(make a worktree), `check` (is this worktree clean, on what ref,
how stale — a verdict, no mutation), `exit` (leave the
worktree you are in: refuse if dirty, else release it and
print the conductor's path for `cd`), `release` (remove
a worktree; dirty refuses), and `list` (all worktrees incl.
stale).

Worktree state (owner, Round 4): bookkeeping stores creation
facts only (`run_id`, quest, exp, actual path, requested
ref, timestamps). Dirty, stale, missing, and orphaned are
**derived conditions**, recomputed from git and the
filesystem whenever asked — never stored states that can
lie between updates. On release the physical worktree is
removed and the bookkeeping record is **deleted**: no
tombstone. The Run's ledger lines, run folder, and tape
already carry its history; a released Run ID may be
prepared again if a child exited too early. A tombstone
enters only if Run ID collisions or a worktree-release audit
become observed needs.

Function safety (owner, Round 5): the dirty-worktree refusal
lives in the **util remove primitive itself** — it
inspects before removing and refuses a dirty worktree no
matter who calls it; `--force` is an explicit parameter
no caller can omit silently. Bookkeeping orchestrates
records around the primitive, but cannot bypass the
check. This matches the codebase's instinct: invariants
sit at the lowest writer, not in caller discipline.

Addressing (owner, Rounds 2–3): `run_id` is the primary
key. `prepare` also takes quest and exp because it needs
creation context — which branch and which path namespace
— but later lifecycle operations resolve the worktree by
`run_id` through bookkeeping. The default path is a
hard-coded derivation inside the tool,
`.bp3/worktrees/<quest>/<exp>/<run-id>/`; the returned
path in verdicts is output, never the primary input.
One escape hatch: `prepare --path <dir>` places the worktree
elsewhere (another disk, CI scratch). Bookkeeping
records that actual path under the same `run_id`, so
primary-key addressing keeps working; an unrecorded
path is never guessed.

`prepare` is idempotent per `run_id` (owner, Round 1):
an existing worktree returns
`{ok:true, existing:true, path, ref}` — a child resumed
after a dead session re-enters its worktree without
check-then-branch logic in its prompt. Idempotency is
safe here because a worktree is machine-local furniture, not
ledger state (unlike exp create, which refuses
`E_EXISTS`).

## Success picture

### Landing record (2026-11-14, owner-landed)

Both exps landed through `bp3 q` (rollup `landed`, inbox
empty): exp-1-util-layer c1 (`2c8ad7f4`), exp-2-bookkeeping
c2 (`fab11525`) after one blocked cycle and an owner
resume. The parallel-prepare registry race found in
review became a settled convention — one file per key,
`.bp3/desks/<run_id>.json` — with its regression case in
`test/worktree.sh` and the full suite green in
`make check`. The landing sweep observed
`bp3 worktree list` returning zero worktrees.

Limitations, plainly: no workflow consumes the verbs
yet — `induct-exp` still runs children in the shared
tree. Conventions and adoption belong to the
bp3-workflows-v2 quest (its Exp 4), which is the first
real consumer; the toy-exp end-to-end picture below is
therefore still a design trace, not an observed run.

A toy exp driven end to end while `git branch
--show-current` in the conductor's tree never changes;
two graders read the same bound commit concurrently from
separate worktrees; releasing a dirty worktree refuses; stale
worktrees from killed Runs are listed and sweepable.

Quest close-out (conventions layer): worktree closing is
two-level. The normal path is Run level: each Run exits
its own worktree on clean settle (`bp3 worktree exit`).
If a Run blocks with dirty work, it checkpoints first
when possible; otherwise the worktree is preserved and
its path is surfaced in the human inbox. The second
level is the quest audit/sweep: when a quest lands,
**all of its worktrees close**. As part of the landing
ceremony the conductor lists the quest's remaining
worktrees and releases every clean straggler. After
correct Run-level exits, that sweep should normally find
zero; anything found means a Run leaked. A dirty
worktree is never force-released to make the number
zero — it blocks the landing record until it is
checkpointed, resumed, or released under an explicit
owner-named `--force`. Zero open worktrees for the
quest is part of what "landed" means, checkable in the
landing demo. The workflows-v2 icebox entry carries the
same convention as a TODO for the step-function split.

## Scope

| In | Out |
|---|---|
| Util, bookkeeping, and conventions layers behind `bp3 worktree`, with `.bp3/worktrees/` as the default worktree root | any ledger/state representation of worktrees |
| workflow adoption of any kind | the workflows-v2 split and its worktree conventions (that quest consumes this one; see icebox) |
| stale-worktree sweep on release/list | auto-deleting dirty worktrees, ever |

## Human touchpoints

Quest approval (this file, incl. the shell-vs-CLI call);
promotion decision at landing. No per-Run human gates.

## Exps

### Exp 1 — [Util layer](experiments/exp-1-util-layer/NODE.md)
Low-level worktree mechanics only: hard-coded path
derivation, create/remove a worktree on a branch or
detached commit, and ref/dirty inspection. No registry,
override, staleness policy, or workflow behavior.
Depends on: none. Lane: standard.

### Exp 2 — [Bookkeeping layer](experiments/exp-2-bookkeeping/NODE.md)
The machine-local registry keyed by `run_id`: worktree
records and path overrides, lifecycle composition behind
`prepare`, plus `check`, `exit`, `list`, and staleness.
Depends on: Exp 1. Lane: standard.

### Exp 3 — deferred to bp3-workflows-v2
Conventions and adoption (author on the exp branch,
review/check detached at the bound commit, two-level
closing in real workflows) are owned by the
[bp3-workflows-v2 quest](../2026-11-14-bp3-workflows-v2/GRAPH.md)
(its Exp 4 — Desks), settled by the owner 2026-11-14:
the v2 split is the first workflow consumer, not
today's monolith. This quest ships util + bookkeeping.

## Scorecard

| Field | Value |
|---|---|
| Wall time / context tokens | measured by hook `usage_recorded` lines on the driving Runs |
| Human-active minutes | approval + landing gate |

## Risks and red chair

| Attack | What it changed |
|---|---|
| Just use Muse's workflow `isolation` flag | kept as an allowed host alternative, but bp3 cannot depend on a Muse-only feature (other engines, shell-driven Runs) |
| Worktrees as `bp3 q` state | rejected: machine-local facts stay out of the ledger, same rule as the hook registry (`.git/bp3-run-registry.json`) |
| Release deleting real work | release refuses dirty worktrees; force is explicit and named; no auto-sweep of dirty worktrees, ever |
| Another bash surface to keep in sync | verbs are thin git wrappers with JSON verdicts; path derivation mirrors branch derivation already in the OCaml core, and fixtures pin both |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | ~~Placement~~ — settled 2026-11-14: `bp3 worktree` surface, OCaml-owned implementation, `check`/`exit` included | settled |
| 2 | ~~Adoption consumer~~ — settled 2026-11-14: bp3-workflows-v2 handles adoption; this quest is util + bookkeeping only | settled |
