---
date: 2026-11-15
quest: ../../QUEST.md
exp: 6
status: proposed
---

# Exp 6 — Member desk lifecycle: engine dirt is not author dirt (follow-up)

## TL;DR

Follow-up from an **observed** dogfood wart (2026-11-15,
demo-routes): after a member lands from its own desk,
the desk's working copy shows `ledger.jsonl` and
`state.yaml` as staged modifications — the engine wrote
state through git plumbing on the exp branch, and the
desk's checkout of that same branch now disagrees with
its own index. `bp3 worktree release` then refuses
(`E_DIRTY_TREE`) on dirt the author never made, and the
conductor must `--force` a desk whose real work is
safely landed. Fix: `bp3 worktree check`/`release`
classify dirt — changes under the quest's generated
paths (`docs/quests/**/(ledger.jsonl|state.yaml)`) are
**generated dirt**, reported separately
(`generated_dirty: true, dirty: false-for-authors`), and
release refreshes exactly those files from the branch
tip before its dirty test instead of refusing. Author
dirt (anything else) still refuses, unchanged. Member
desks are released at the **stage barrier** by the
conductor (Exp 2 calls this at stage close), so desks
live one stage, not one quest.

## Demo (observed + design trace)

Observed, 2026-11-15, demo-routes member desk after land:

```text
$ git -C .bp3/worktrees/demo-routes/exp-a-marker/demoA status --short
M  docs/quests/demo-routes/experiments/exp-a-marker/ledger.jsonl
M  docs/quests/demo-routes/experiments/exp-a-marker/state.yaml
$ ./bin/bp3 worktree release --run demoA
{"ok":false,"error":{"code":"E_DIRTY_TREE", ...}}     (conductor had to --force a landed desk)
```

After this exp (design trace):

```text
$ ./bin/bp3 worktree check --run demoA
{"ok":true, ..., "dirty":false, "generated_dirty":true, "changed_count":2}
$ ./bin/bp3 worktree release --run demoA
{"ok":true,"released":true,"removed":true, ...}      (generated files refreshed from tip, then released)
```

## Diagram

```text
worktree check/release ─► changed files ─► all under quest generated paths?
                                             ├─ yes ─► refresh from branch tip ─► clean ─► release proceeds
                                             └─ any author file ─► E_DIRTY_TREE (unchanged refusal)
stage barrier (Exp 2) ─► release member desks of the closed stage
```

## Pseudocode

```python
GENERATED = r"docs/quests/.*/experiments/.*/((ledger\.jsonl)|(state\.yaml))$"

def classify(changed_paths):
    gen = [p for p in changed_paths if matches(GENERATED, p)]
    author = [p for p in changed_paths if p not in gen]
    return author, gen

def release(run):
    author, gen = classify(changed(run))
    if author: refuse E_DIRTY_TREE(author)
    checkout_from_tip(gen)          # engine's own writes, refreshed not judged
    remove_worktree(run)
```

## Tables

| Field | Value |
|---|---|
| Intent | a desk's release judges the author's work, never the engine's own plumbing |
| Lane | standard |
| Output | dirt classification in `src/quest/worktree.ml` (`check`, `release`, list's `dirty` fields gain `generated_dirty`); fixtures in `test/worktree.sh` |
| Acceptance | cases below; the headline case is observed above |
| Depends on | Exp 2 (barrier-time release calls it) |

| Case | Expected after |
|---|---|
| desk with only generated dirt after land | `check` reports `generated_dirty: true`, `dirty: false`; release succeeds without `--force` |
| desk with one author file changed | release refuses `E_DIRTY_TREE` naming that file, generated refresh does not rescue it |
| desk with both | refusal lists only the author files |
| `worktree list` during a stage | member desks show generated vs author dirt distinctly |
| per-Run desks (pre-Exp-8 behavior) | same classification (the wart predates quest desks) |
| refresh correctness | refreshed `ledger.jsonl` in a re-prepared desk equals the branch tip's, byte-for-byte |

## Acceptance test (goal block)

- **Objective:** engine-made dirt never blocks a desk
  release; author dirt always does.
- **Prove by:** reproduce the demo-routes trace in
  `test/worktree.sh` (land from a desk, then check +
  release without force), the mixed-dirt refusal, and
  the byte-equality re-prepare case; `make check` green.
- **Done when:** the observed wart's exact trace now
  ends in a clean release, and mixed dirt still refuses.

## Prose

Why classify instead of refreshing unconditionally at
land time: the desk may hold a *second* cycle's
uncommitted author work when a grade returns; a land
edge that silently refreshes files underneath the
author would eat exactly the work the desk exists to
protect. Classification at release keeps the judgment
at the moment of teardown, where dirt is expected to be
explained. Why generated paths are scoped to the quest's
own experiments: a blanket `ledger.jsonl` pattern would
let an author hide real edits in any quest's generated
files — the refresh must only ever touch files the
engine itself writes, in the desk's own quest.

## Tests

unit: none · fixtures: land-from-desk lifecycle,
mixed-dirt refusal, re-prepare byte equality in
`test/worktree.sh` · demos: the observed demo-routes
trace, replayed at review
