---
name: using-bp3
description: "Operate bp3 correctly in this repo: quest folders, bp3 invoke edges, ledger discipline, and verification, for any Controller or Worker session."
---
<!-- GENERATED from skills/using-bp3/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->

# Using bp3

Use when working in the bp3 repo and the task touches quest
state: starting a quest, advancing one, recording a review or a
blocker, landing, or recovering after a dead session. Invoked by
a human, Controller, or Worker by name (`/using-bp3`,
`$using-bp3`). One output: bp3 operations performed through
`bp3 invoke`, with state read from its JSON verdicts.

Use `quest` instead to frame a new quest's intent and shape.
Use `bp3-writer` instead to write an exp's canonical record.
General coding in this repo does not need this skill.

## Procedure

1. Read state first: `./bin/bp3 invoke <quest>` (or
   `./bin/bp3 invoke list`). Never read `state.yaml`,
   `ledger.jsonl`, or `fsm.yaml` by hand to decide anything.
2. Start quests with `./bin/bp3 invoke init <name> --type <quest_type>
   --engine <engine>`. It scaffolds `docs/quests/<name>/`
   (QUEST.md, fsm.yaml, state.yaml, ledger.jsonl, runs/).
   Two independent dimensions: `quest_type` is the plan in
   `plans/` (default: one review round), `engine` is who
   executes (single, master-subagents, panes, workflows).
3. Take only legal moves. The verdict JSON lists them:
   `submit --commit <sha>`, `review --verdict ship|fix_first`,
   `land`, `block`, `cancel`. Judgment moves need `--reason`;
   it is the move's commit message. Verdicts bind to the exact
   current commit; a second `fix_first` at the cycle cap
   escalates to blocked — do not work around it.
4. Commit work before submitting it. Only clean commits move:
   `submit` refuses dirty trees outside quest folders and
   commits that do not descend from the recorded state.
5. Recover from the ledger, not from memory: after a dead
   session, `bp3 invoke <quest>` rebuilds state from
   `ledger.jsonl`. Transcripts and tapes are evidence, never
   state, and tape is never parsed into facts.
6. Verify with `make check` and report exactly what ran.

## Rules

- Never hand-edit `state.yaml` or `ledger.jsonl`. If a move was
  not taken through `bp3 invoke`, it did not happen.
- Status is a frontmatter field in `QUEST.md`
  (`proposed | active | landed | canceled`), never a folder.
  Quest paths never move; links and exp records point at them.
- A reviewer who refactors takes a fix edge and produces a new
  commit; the new commit needs a fresh review.
- Teach before building on a new quest or design: concept,
  before, change, after, bites, transfer cues — then the nod.
- Instructions only: this skill holds no state and writes no
  Board, ledger, or state itself; `bp3 invoke` does that.
