# bp3 — agent instructions

bp3 is a quest state engine. Work moves as clean git commits;
a small OCaml binary (`bp3 invoke`) is the only writer of quest
state. Read this before touching anything under `docs/quests/`.

## The one rule

Never hand-edit generated quest state. `state.yaml` and
`ledger.jsonl` in a quest folder are written only by
`bp3 invoke`. Never parse them by hand to decide anything either:
run `bp3 invoke <quest>` and read its JSON verdict.

## Layout

```text
docs/quests/<quest>/     one folder per quest, flat, never moved
  QUEST.md               authored: goal, scope, exps, status field
  fsm.yaml               authored: the plan (from plans/ at init)
  state.yaml             GENERATED: stage, commit, cycle (a cache)
  ledger.jsonl           GENERATED: every move, append-only (truth)
  runs/<id>/             tape.log (verbatim), notes.md (lessons)
plans/<type>.yaml        quest_type plans (default: one review round)
invoke/main.ml           the state engine (OCaml, yojson + unix)
docs/dossiers/           research records; they inform, never decide
experiments/ inside each quest folder: one record per exp
```

Status is a frontmatter field in `QUEST.md`
(`proposed | active | landed | canceled`), never a folder.
A quest's path must survive its whole life: exp records and
other repos point at it.

## Commands

```sh
./bin/bp3 init   # one-time repo setup: renders skills for all harnesses
./bin/bp3 quest create <name> --type default --engine single
./bin/bp3 invoke <quest>            # JSON: stage, commit, legal moves
./bin/bp3 invoke <quest> submit --commit <sha> --reason "..."
./bin/bp3 invoke <quest> review --verdict ship|fix_first --reason "..."
./bin/bp3 invoke <quest> land --reason "..."
./bin/bp3 quest list                 # active quests; --all includes landed/canceled
./bin/bp3 quest show <quest>          # one quest, JSON
dune build invoke/main.exe          # (make check does this)
make check                          # lint, skills, invoke fixture tests
```

Two independent dimensions: `quest_type` is the plan (stages and
gates, YAML in `plans/`), `engine` is who executes (single,
master-subagents, panes, workflows). A reviewer who refactors
takes a fix edge and produces a new commit; verdicts always bind
to the exact commit reviewed.

## Working agreements

- Teach before building: when a quest or design is new, teach the
  concepts back to the human (concept, before, change, after,
  bites, transfer cues) and get the nod before implementation.
- One review round by default (`max_cycles: 1`): a second
  `fix_first` escalates to the human instead of looping.
- Ledger is truth; `state.yaml` is its cache. Refused moves are
  ledgered too. Only clean commits move — dirty worktrees are
  never state.
- Tape is evidence, never parsed into facts. Ledger lines are
  emitted deliberately at the moment a fact happens.
- Integration branch is `master`. Quest work lives on
  `quest/<slug>` branches until the human promotes it. Commits
  use the bp3 format (TL;DR, For humans, For LLMs) via `/commit`.
- Verify with `make check` and say plainly what was not run.
  Never claim a gate passed that was dropped or skipped.
