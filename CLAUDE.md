# bp3 — agent instructions

bp3 is a quest state engine. Work moves as clean git commits;
a small OCaml binary (the `bp3 q` door) is the only writer of
quest state. Read this before touching anything under the
quest storage tree (`docs/quests/`: one folder per quest; a
quest is the DAG of nodes it plans).

## The one rule

Never hand-edit generated quest state. `state.yaml` and
`ledger.jsonl` in a quest folder are written only through
`bp3 q`. Never parse them by hand to decide anything either:
run `bp3 q r <quest>` and read its JSON verdict.

## Layout

```text
docs/quests/<quest>/     one folder per quest, flat, never moved
  QUEST.md              authored: goal, scope, nodes, status field
  fsm.yaml               authored: the plan (from plans/ at init)
  state.yaml             GENERATED: stage, commit, cycle (a cache)
  ledger.jsonl           GENERATED: every move, append-only (truth)
  runs/<id>/             tape.log (verbatim), notes.md (lessons)
plans/<type>.yaml        goal_type plans (default: one review round)
src/quest/main.ml        the state engine (OCaml, yojson + unix)
docs/dossiers/           research records; they inform, never decide
nodes/ inside each quest folder: one record per node
```

Status is a frontmatter field in `QUEST.md`
(`proposed | active | landed | canceled`), never a folder.
A quest's path must survive its whole life: node records and
other repos point at it.

## Commands

```sh
./bin/bp3 init   # one-time repo setup: renders skills for all harnesses
./bin/bp3 q c <quest> --type default   # create a quest
./bin/bp3 q r <quest>                  # rollup JSON: nodes, states, legal edges
./bin/bp3 q <quest> n <node> r         # read one node
./bin/bp3 q <quest> n <node> e handoff --commit <sha> --reason "..."
./bin/bp3 q <quest> n <node> e grade --verdict ship|needs_fix --reason "..."
./bin/bp3 q <quest> n <node> e land --reason "..."
./bin/bp3 e                            # claimed edge door: resolved context
./bin/bp3 n r                          # claimed node door: read own node
dune build src/quest/main.exe          # (make check does this)
make check                             # lint, skills, CLI fixture tests
```

Two independent dimensions: `goal_type` is the plan (stages and
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
