# bp3 — agent instructions

bp3 is a quest state engine. Work moves as clean git commits;
a small OCaml binary (the `bp3 q` door) is the only writer of
quest state. Read this before touching anything under the
quest storage tree (`docs/quests/`: one folder per quest; a
quest is the DAG of nodes it plans).

## The one rule

Never hand-edit generated quest state. `state.yaml` and
`ledger.jsonl` in a quest folder, and `metrics.jsonl` in a node
folder, are written only through `bp3 q`. Never parse them by
hand to decide anything either:
run `bp3 q r <quest>` and read its JSON verdict.

## Constraints and context

[CONSTRAINTS.md](CONSTRAINTS.md) is the owner-signed stack: the
languages bp3 is written in, the libraries each may use, and the
surfaces it ships. Adding any of them takes a `/teach` pitch and the
owner's words in its Sign-off log; `make lint` checks the files
against it. [CONTEXT.md](CONTEXT.md) is how others build agent
harnesses, one sourced and dated claim per line. Read both before
planning or grading; re-check a claim older than 90 days before
citing it.

## Layout

```text
docs/quests/<quest>/     one folder per quest, flat, never moved
  QUEST.md              authored: plan of record (goal, scope, gates, status)
  LOG.md                authored: living run log (nodes, build notes, findings, lessons)
  FEEDBACK.md           authored: post-quest human feedback, Warden audit, proposals, disposition
  fsm.yaml               authored: the plan (from plans/ at init)
  state.yaml             GENERATED: stage, commit, cycle (a cache)
  ledger.jsonl           GENERATED: every move, append-only (truth)
  runs/<id>/             tape.log (verbatim), notes.md (lessons)
plans/<type>.yaml        goal_type plans (default: up to ten review rounds)
src/quest/main.ml        the state engine (OCaml, yojson + unix)
src/warden/              two-layer deterministic Warden plug engine (bp3_warden)
docs/dossiers/           research records; they inform, never decide
nodes/ inside each quest folder: one record per node, plus
  metrics.jsonl          GENERATED: grade and author cost samples (bp3 q <quest> metrics)
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
./bin/bp3 q <quest> n <node> brief [--desk <path>]   # the grader's cold brief, rendered from the bound commit (GRADING.md)
./bin/bp3 q <quest> metrics scrape|r   # collect, then read, what grades and author cycles cost
./bin/bp3 warden [<quest>] [--last N|--all] [--no-sessions] [--format json|table]  # two-layer deterministic plug audit (read-only)
./bin/bp3 e                            # claimed edge door: resolved context
./bin/bp3 n r                          # claimed node door: read own node
dune build src/quest/main.exe          # (make check does this)
make check                             # inner loop: lint, dune test, unit tier (seconds)
make check-full                        # grade/land gate: check + fixture and slow tiers
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
- Up to ten review rounds by default (`max_cycles: 10`, owner
  2026-11-21: "increase the rounds to 10, i do not want to be
  involved"; was 3 since 2026-11-19): a `needs_fix` below the cap
  returns the node to todo for another round; one at the cap
  escalates to the human.
- Ledger is truth; `state.yaml` is its cache. Refused moves are
  ledgered too. Only clean commits move — dirty worktrees are
  never state.
- Tape is evidence, never parsed into facts. Ledger lines are
  emitted deliberately at the moment a fact happens.
- Integration branch is `master`. Quest work lives on
  `quest/<slug>` branches until the human promotes it. Commits
  use the bp3 format (TL;DR, For humans, For LLMs) via `/commit`.
- Verify with `make check` while working and `make check-full`
  before handoff (the grade/land gate); say plainly what was not run.
  Never claim a gate passed that was dropped or skipped.
