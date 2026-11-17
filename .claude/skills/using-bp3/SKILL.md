---
name: using-bp3
description: "Operate bp3 correctly in this repo: graph folders, bp3 g edges, ledger discipline, and verification, for any Controller or Worker session."
---
<!-- GENERATED from skills/using-bp3/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# Using bp3

Use when working in the bp3 repo and the task touches graph
state: starting a graph, advancing one, recording a review or a
blocker, landing, or recovering after a dead session. Invoked by
a human, Controller, or Worker by name (`/using-bp3`,
`$using-bp3`). One output: bp3 operations performed through
`bp3 g`, with state read from its JSON verdicts.

Use `graph` instead to frame a new graph's intent and shape.
Use `bp3-writer` instead to write an node's canonical record.
General coding in this repo does not need this skill.

## Procedure

1. Read state first: `./bin/bp3 g show <graph>` (or
   `./bin/bp3 g list` for active graphs, `--all` for every graph). Never read `state.yaml`,
   `ledger.jsonl`, or `fsm.yaml` by hand to decide anything.
2. Start graphs with `./bin/bp3 g create <name> --type <graph_type>
   --engine <engine>`. It scaffolds `docs/graphs/<name>/`
   (GOAL.md, fsm.yaml, state.yaml, ledger.jsonl, runs/).
   Two independent dimensions: `graph_type` is the plan in
   `plans/` (default: one grade round), `engine` is who
   executes (single, master-subagents, panes, workflows).
3. Graph dependencies live in `fsm.yaml` as `depends_on: [...]`
   (set at create with `--depends-on`). `handoff` refuses until
   every dependency's stage is `landed`; the verdict JSON shows
   `blocked_by`. Dependencies are by graph folder name.
4. Take only legal moves. The verdict JSON lists them:
   `handoff --commit <sha>`, `grade --verdict ship|fix_first`,
   `land`, `block`, `cancel`. Judgment moves need `--reason`;
   it is the move's commit message. Verdicts bind to the exact
   current commit; a second `fix_first` at the cycle cap
   escalates to blocked — do not work around it.
5. Commit work before handing it off. Only clean commits move:
   `handoff` refuses dirty trees outside graph folders and
   commits that do not descend from the recorded state.
6. Recover from the ledger, not from memory: after a dead
   session, `bp3 g r <graph>` rebuilds state from
   `ledger.jsonl`. Transcripts and tapes are evidence, never
   state, and tape is never parsed into facts.
7. Verify with `make check` and report exactly what ran.

## Rules

- Never hand-edit `state.yaml` or `ledger.jsonl`. If a move was
  not taken through `bp3 g`, it did not happen.
- Status is a frontmatter field in `GOAL.md`
  (`proposed | active | landed | canceled`), never a folder.
  Graph paths never move; links and node records point at them.
- A reviewer who refactors takes a fix edge and produces a new
  commit; the new commit needs a fresh review.
- Teach before building on a new graph or design: concept,
  before, change, after, bites, transfer cues — then the nod.
- Instructions only: this skill holds no state and writes no
  Board, ledger, or state itself; `bp3 g` does that.
