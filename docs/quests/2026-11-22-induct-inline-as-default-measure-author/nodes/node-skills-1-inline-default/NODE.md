---
date: 2026-11-22
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - inline-default: induct-inline is how a quest runs (skill node)

## TL;DR

induct-inline becomes the default conductor, and using-bp3 and induct
say so. Its grade step changes in four ways: the brief comes from
`bp3 q <quest> n <node> brief`, passed verbatim; each grader works in a
grade desk at its commit; grades run in the background while the
author takes the next ready node; and finished verdicts are cast only
at a cast boundary. A g.sh fixture proves bp3 lands two nodes committed
one on top of the other in one desk.

## Acceptance gates

Observed today:

```text
$ grep -n 'n <node> brief' skills/induct-inline/SKILL.md          # rc=1
$ grep -n 'one node in flight' skills/induct-inline/SKILL.md       # Rules: "One quest, one session, one node in flight."
$ grep -n 'induct-inline' skills/using-bp3/SKILL.md                # rc=1: using-bp3 names no default conductor
```

Design trace:

```text
$ ./test/skills.sh
  induct-inline (source and every render): "the default way to run a quest"; `bp3 q <quest> n <node> brief`; "verbatim";
    `bp3 harness worktree prepare <quest> <node> --run grade-<node>-c<cycle>-a<attempt> --commit <sha>`; "cast boundary";
    "clean at the bound commit" before a cast; a void verdict re-dispatches with the next attempt;
    "one session per quest"; no "one node in flight"
  using-bp3 and induct name induct-inline as the default, and induct as the mode for many independent nodes at once
$ ./test/g.sh
  one desk: commit A, handoff nd1; commit B on top, handoff nd2; grade nd1 ship, land nd1 (merge); grade nd2 ship, land nd2
  -> both landed, quest tip contains A and B, the desk's `git status --short` empty
```

```yaml
objective: a fresh session runs a quest inline from the skill alone, with background grades that keep author windows exact
prove by:
  - test/skills.sh new assertions (render and install with BP3_COMPLETIONS_DIR in scratch)
  - test/g.sh: the two-commit land fixture
  - dogfood: this quest's measure.1 and brief.1 overlapped, both landed (build notes cite the ledger stamps)
  - make check-full
done when: the assertions pass and fail on master's text, the fixture passes, and the dogfood overlap is recorded
```

## Diagram

```text
read ──> handed_off, no grader? ──> grade desk at sha ──> grader (background, rendered brief)
  │
  ├──> ready todo, nothing being authored? ──> author in the quest desk ──> commit ──> handoff
  │                                                                          │
  │                                              cast boundary <─────────────┘
  │                                              (also: nothing left to author)
  │                                                    │
  │                     cast finished verdicts, in handoff order; land approved; release grade desks
  └──< re-read <───────────────────────────────────────┘
```

## Pseudocode

```python
def conduct(quest):
    desk = prepare_quest_desk(quest)
    graders = {}                                            # node -> running background grader
    while True:
        r = read(quest)
        for n in r.handed_off:
            if n not in graders:
                a = next_attempt(n)
                gd = worktree_prepare(quest, n, run=f"grade-{n}-c{r.cycle(n)}-a{a}", commit=r.commit(n))
                graders[n] = spawn_background(brief(quest, n, desk=gd))   # verbatim
        todo = [n for n in r.ready if r.state(n) == "todo"]
        if todo:
            author(todo[0], desk); handoff(todo[0])          # one node being authored at a time
        elif not graders and not r.approved:
            return report(r)
        cast_boundary(graders)                               # after a handoff, or nothing to author:
        #   wait only if nothing is left to author; for each finished verdict, in handoff order:
        #   grade desk HEAD == bound commit and `git status --short` empty? cast, land if approved,
        #   release the desk, scrape. Otherwise the verdict is void: keep the desk, drop the grader
        #   from graders, so the next read dispatches attempt a+1 in a fresh desk
```

## Tables

| Field | Value |
|---|---|
| Intent | the measured way becomes the written default, and it gets faster |
| Lane | micro (skill node: its own gate, quest skill step 6.6), plus one g.sh fixture |
| Output | `skills/induct-inline/SKILL.md`, `skills/using-bp3/SKILL.md`, `skills/induct/SKILL.md`, renders, `test/skills.sh`, `test/g.sh` |
| Acceptance | test/skills.sh and g.sh assertions; fail today |
| Depends on | brief.2 (the skill promises the scrape checks the brief) |

| Rule | Why |
|---|---|
| grader in a grade desk, never the author's desk | the author keeps committing; a grader must see one fixed tree |
| verify, then cast: desk at the bound commit and clean | a grader's stray edit could turn the gate green on a tree that isn't the bound commit (red-ink round 5) |
| one desk per attempt, `-a<attempt>` | `worktree prepare` reuses a desk with the same run id; a re-dispatched grader must not inherit leftovers |
| cast only at a cast boundary | every author window then holds one node's work; `author_spans` stays exact (measure.1) |
| background only for nodes `ready` lists | `ready` already means deps landed; one writer per node (CONTEXT.md:22) |
| brief verbatim from `bp3 … brief` | the author never words the grader's instructions; brief.2 checks |
| one session per quest | context stays one quest wide; NODE build notes carry state across a compaction |
| `induct` stays for many independent nodes at once | fan-out with workflow children is still there when a quest is wide |

## Prose

The old rule, "one node in flight", made the author wait out every
grade. The new rule is one node being authored, and any number graded.
The author is still the only writer. Graders never write, they each
work in their own detached checkout, and they never see the author's
working tree.

The cast boundary is what keeps measure.1 exact. An author window runs
from the quest's latest edge to the handoff. If a background verdict
were cast in the middle of authoring, that cast would become the latest
edge, and the window would start late and undercount. Casting only
right after a handoff (or when there's nothing left to author) means
the edges inside a window are always the previous node's own.

A `needs_fix` on a background-graded node puts the fix on top of
another node's commit. The cycle-2 brief lists that commit (brief.1),
so the grader judges only its own node's change. bp3's land already
merges when the quest tip isn't an ancestor. What hasn't been shown is
that this works while the branch is checked out in a desk. The quest
probes it in a scratch clone before its first stacked land (QUEST.md,
red-ink round 4), and the g.sh fixture here is the regression test. If the dogfood finds a break, the fallback is
background grades with serial handoffs, and the skill text says so.

## Tests

Known cases: the skills.sh patterns above, each absent from master's
text (checked one by one, as pi-metrics skills.1 did), and the g.sh
two-commit land. Property-based: omitted. Skill text has no generator,
and the land fixture covers one shape, the one the skill creates.
