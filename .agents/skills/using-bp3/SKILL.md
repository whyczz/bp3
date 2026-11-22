---
name: using-bp3
description: "Operate bp3 correctly in this repo: quest folders, bp3 q edges, ledger discipline, and verification, for any Controller or Worker session."
---
<!-- GENERATED from skills/using-bp3/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->

# Using bp3

Use when working in the bp3 repo and the task touches quest
state: starting a quest, advancing one, recording a review or a
blocker, landing, or recovering after a dead session. Invoked by
a human, Controller, or Worker by name (`/using-bp3`,
`$using-bp3`). One output: bp3 operations performed through
`bp3 q`, with state read from its JSON verdicts.

Use `quest` instead to frame a new quest's intent and shape.
Use `bp3-writer` instead to write an node's canonical record.
General coding in this repo does not need this skill.

## Procedure

1. Read state first: `./bin/bp3 q show <quest>` (or
   `./bin/bp3 q list` for active quests, `--all` for every quest). Never read `state.yaml`,
   `ledger.jsonl`, or `fsm.yaml` by hand to decide anything.
2. Start quests with `./bin/bp3 q create <name> --type <quest_type>
   --engine <engine>`. It scaffolds `docs/quests/<name>/`
   (QUEST.md, fsm.yaml, state.yaml, ledger.jsonl, runs/).
   Two independent dimensions: `quest_type` is the plan in
   `plans/` (default: up to ten review rounds), `engine` is who
   executes (single, master-subagents, panes, workflows).
3. Quest dependencies live in `fsm.yaml` as `depends_on: [...]`
   (set at create with `--depends-on`). `handoff` refuses until
   every dependency's stage is `landed`; the verdict JSON shows
   `blocked_by`. Dependencies are by quest folder name.
4. Take only legal moves. The verdict JSON lists them:
   `handoff --commit <sha>`, `grade --verdict ship|needs_fix`,
   `land`, `block`, `cancel`. Judgment moves need `--reason`;
   it is the move's commit message. Verdicts bind to the exact
   current commit; a `needs_fix` at the cycle cap
   escalates to blocked — do not work around it.
5. Commit work before handing it off. Only clean commits move:
   `handoff` refuses dirty trees outside quest folders and
   commits that do not descend from the recorded state.
6. Recover from the ledger, not from memory: after a dead
   session, `bp3 q r <quest>` rebuilds state from
   `ledger.jsonl`. Transcripts and tapes are evidence, never
   state, and tape is never parsed into facts.
7. Verify with `make check` while working and with
   `make check-full` before handoff, grade or land (the
   gate); report exactly what ran.
8. Measure with `./bin/bp3 q <quest> metrics r`: what each grade
   and author cycle cost (wall, tool calls, tokens), each
   cycle's time in todo and handed_off, and node and quest
   roll-ups. `./bin/bp3 q <quest> metrics scrape` collects from
   Claude Code transcripts and is safe to re-run; it exits 1
   when a transcript disagrees with the harness report, which is
   a finding to report, not a failed step. Its samples
   live in `metrics.jsonl` on each node's state branch,
   GENERATED like `ledger.jsonl`: never hand-edit it.

## Rules

- Never hand-edit `state.yaml` or `ledger.jsonl`. If a move was
  not taken through `bp3 q`, it did not happen.
- Status is a frontmatter field in `QUEST.md`
  (`proposed | active | landed | canceled`), never a folder.
  Quest paths never move; links and node records point at them.
- A reviewer who refactors takes a fix edge and produces a new
  commit; the new commit needs a fresh review.
- Teach before building on a new quest or design: concept,
  before, change, after, bites, transfer cues — then the nod.
- Instructions only: this skill holds no state and writes no
  Board, ledger, or state itself; `bp3 q` does that.
