---
date: 2026-11-15
goal: ../../GRAPH.md
exp: 8
status: proposed
---

# Exp 8 — `/induct` gets a quest-level worktree by default

## TL;DR

Every `/induct` (and `/induct-goal-no-human`) runs its
quest in **one quest-level worktree** from first dispatch
to `goal_fin`: `.bp3/worktrees/<quest>/` on branch
`quest/<quest>`, prepared before the first step, released
only when the quest is terminal or the owner says stop.
All step children (author, graders, land) work inside it;
the conductor's checkout is never worked in, so parallel
inducts of different quests — and the owner working on
`master` — cannot dirty, block, or land on each other.
This exp builds the missing mechanism, not just the rule:
a quest-level prepare mode in `bp3 worktree`, desk-aware
step workflows (children receive and use the desk path),
and the `induct` skill text that makes it the default.

Skill changes ride as their own exp (quest skill 6.6):
this is that exp — `skills/induct`,
`skills/induct-goal-no-human`, and the induct workflows
change here, with their own acceptance, never inline in
another exp's Run.

## Red chair (at framing, 2026-11-15, owner-invoked)

Engineering lens. Verdict: ship, mechanism-first.

| # | Attack (severity) | What it changed |
|---|---|---|
| 1 | **[critical]** Quest-level desks don't exist: `bp3 worktree prepare` is per `<quest> <exp> --run`, and no step workflow references a worktree — children spawn shared. A default rule without mechanism is fiction. | The exp is mechanism-first: quest-level prepare + desk-aware workflows are deliverables 1–2; the skill text lands last and must not claim what the steps can't do |
| 2 | **[major]** This very quest proved the wart: Exp 3's submit refused `E_DIRTY_TREE` from the owner's parallel master work; Exps 1–3's content commits stacked onto `master`. The bp3-worktrees quest recorded the same class (child commits on another exp's branch, tape blocking a branch switch). | Acceptance includes the parallel-induct demo: two quests inducting at once, owner editing master, zero cross-talk |
| 3 | **[major]** Desks under `.bp3/worktrees/` nest inside the repo: `dune build` walks up to the parent project and fails (`Don't know how to build`) until `--root=.` — observed live in this quest's desk. | Acceptance case: build + `test/q.sh` inside a fresh quest desk with no flags from the child; the fix (Makefile/worktree-aware build or desk path outside the dune walk) is named in the exp, not left to children to rediscover |
| 4 | **[minor]** Per-Run desks (bp3-worktrees S1–S3) isolate more strongly; quest-level is coarser. | Survives: the railway is serial per quest, and parallel inducts means parallel quests. Recorded reversal: if parallel graders within one quest become real, per-Run desks replace this default and this exp is revisited |

What would change the verdict: evidence that grade
children within one quest must run concurrently against
different commits (fan-out groups landing, not just
exploring) — attack 4 then wins and this exp is cut.

## Demo (design trace)

```text
$ ./bin/bp3 worktree prepare --quest 2026-11-14-bp3-cli-small-fixes
{"ok":true,"quest":"2026-11-14-bp3-cli-small-fixes",
 "path":".bp3/worktrees/2026-11-14-bp3-cli-small-fixes","ref":"quest/2026-11-14-bp3-cli-small-fixes","existing":false}

# conductor dispatches every step with the desk as cwd;
# owner meanwhile commits freely on master — no interaction:
$ ./bin/bp3 q 2026-11-14-bp3-cli-small-fixes u exp-3-icebox-search submit --commit <desk-commit> --reason "..."
{"ok":true, ...}        (from inside the desk; master dirty the whole time)

# parallel: a second induct of another quest prepares its own desk;
# bp3 worktree list shows both, neither in the shared tree.

$ ./bin/bp3 worktree release --quest 2026-11-14-bp3-cli-small-fixes   # at goal_fin or owner stop
{"ok":true,"released":true}    (dirty desk -> E_DIRTY_TREE, desk preserved)
```

Today (observed): no `--quest` mode (`worktree prepare`
requires `<quest> <exp> --run`); induct steps work in the
shared checkout; this quest's own desk was hand-made with
raw `git worktree add` mid-run after Exp 3's refusal.

## Diagram

```text
/induct <quest> ─► bp3 worktree prepare --quest <quest> ─► .bp3/worktrees/<quest>/ (branch quest/<quest>)
                                                              │ all steps dispatched with cwd = desk
                        author / grade / land children ───────┤ commit, submit, review, check, land
                                                              │ BP3_ROOT = desk; _build in desk (dune --root fixed)
owner on master ──────────────────────────────────────────────┴─ never read, never dirtied, never blocked
quest terminal ─► conductor report ─► worktree release --quest (dirty refuses, per S4)
parallel inducts: one desk per quest; registry in .bp3/desks/ names them all
```

## Pseudocode

```python
def induct(quest):
    desk = worktree_prepare_quest(quest)          # idempotent; branch quest/<quest>
    while (s := read(quest, cwd=desk)).rollup != terminal:
        step = dispatch_for(s, cwd=desk)          # children inherit desk as working dir
        run(step)
    report(...)
    # release is the owner's word or goal_fin ceremony — never automatic on a dirty desk

# bp3 worktree gains:
#   prepare --quest <q>          -> one record keyed quest:<q>, path .bp3/worktrees/<q>
#   release --quest <q>          -> exit semantics of per-run release, quest key
```

## Tables

| Field | Value |
|---|---|
| Intent | parallel inducts and a working owner never collide: one quest, one worktree, by default |
| Lane | high-blast-radius (touches every induct Run's working directory + two skills + three workflows) |
| Output | quest-level mode in `src/quest/worktree.ml` + CLI; desk-aware `skills/induct/workflows/induct-exp.js`, `induct-grade.js`, `quest-land.js`; `skills/induct/SKILL.md` + `skills/induct-goal-no-human/SKILL.md` default text; installed renders regenerated; fixtures in `test/worktree.sh` + `test/induct.sh` |
| Acceptance | cases below; the headline case fails today (observed above) |
| Depends on | none in this quest's railway (follow-up exp; the quest's own remaining exps are being driven in a hand-made desk as the living demo) |

| Case | Expected after |
|---|---|
| `bp3 worktree prepare --quest <q>` twice | same desk returned (`existing: true`), branch `quest/<q>`, one registry record |
| fresh induct, any exp step | child works in the desk: its commit's tree, tape, and `_build` are in `.bp3/worktrees/<q>/`; shared checkout untouched (`git status` in root identical before/after the Run) |
| owner dirties master mid-Run | submit from the desk succeeds; no `E_DIRTY_TREE` from foreign dirt |
| two quests inducted in parallel | two desks, interleaved steps, both progress; `bp3 worktree list` names both; neither child's commit lands on the other's branch |
| build inside desk | `dune build src/quest/main.exe` (as the Makefile invokes it) and `./test/q.sh` pass in the desk with no `--root` flag supplied by the child |
| release, clean desk | desk removed, registry record gone; release, dirty desk → `E_DIRTY_TREE`, desk and edits preserved |
| no-human fleet | preflight additionally refuses a quest whose desk cannot be prepared; fleet report's worktree sweep lists quest desks |
| skills | `test/skills.sh` asserts the default-worktree text in both induct skills; workflow tests assert children receive the desk path |

## Acceptance test (goal block)

- **Objective:** an induct, by default, never works in
  the conductor's checkout — one quest-level worktree per
  quest, start to finish.
- **Prove by:** the parallel demo as a fixture (two
  scratch quests inducted concurrently from one shared
  checkout, owner-simulated dirt on master throughout);
  root `git status` diffed around a full exp cycle;
  build/test inside a fresh desk; both `make check`s for
  skills (`test/skills.sh`, `test/induct.sh`,
  `test/worktree.sh`) green.
- **Done when:** the two-quest fixture passes with zero
  shared-tree changes, the dune case passes flag-free,
  and both induct skills carry the default as procedure,
  not aspiration.

## Prose

Context: born live, mid-quest — the owner was working on
master in parallel, Exp 3's submit refused on foreign
dirt, and the owner named the papercut: "by default every
/induct needs to have a quest level worktree so we can
have parallel inducts." This quest's remaining exps moved
into a hand-made desk (`.bp3/worktrees/2026-11-14-bp3-cli-small-fixes`,
branch `quest/2026-11-14-bp3-cli-small-fixes`) as the
unpolished first instance; this exp is the polished,
default, mechanism-backed version. Why quest-level, not
the per-Run desks the worktrees quest designed: the
railway is serial within a quest, the parallelism that
actually happens is *across* quests and against the
owner's own master work — one desk per quest isolates
exactly that, with one branch the owner can inspect.
Per-Run desks remain right for parallel graders at one
commit (S3) and compose under this: a quest desk is the
home, Run desks may still spawn inside it. Why the skill
text lands last: attack 1 — a default the steps cannot
execute teaches children to lie in their reports. The
dune nesting wart (attack 3) is included because a desk
every child must special-flag is a desk children will
routinely get wrong; the build must just work there.

## Tests

unit: none (worktree plumbing is fixture-covered today) ·
fixtures: quest prepare/release/list cases in
`test/worktree.sh`, desk-dispatch assertions in
`test/induct.sh`, skill-text assertions in
`test/skills.sh`, two-quest parallel fixture · demos: the
traces above, plus this quest's own hand-made desk as the
observed prototype (noted as hand-made, not mechanism)
