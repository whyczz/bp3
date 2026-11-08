---
name: naming
description: "Choose concrete, short names in bp3's existing vocabulary for quests, exps, skills, plans, engines, and CLI verbs."
---
<!-- GENERATED from skills/naming/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->

# Naming

Use when a human, Controller, or Worker in bp3 must name or
rename something: a quest slug, exp, skill, plan (`quest_type`),
engine, CLI verb, file, or state. Invoked by name (`/naming`,
`$naming`). One output: one recommended name, with the vocabulary
it reuses. A shortlist only when two names genuinely tie.

Use `quest` for framing a quest (it delegates naming here),
`using-bp3` for operating the CLI, and general judgment for
ordinary code identifiers with no bp3 meaning.

## The vocabulary (reuse before inventing)

- Planning: Quest, exp, Run. Lifecycle: proposed, active,
  landed, canceled. Never archived, cancelled, aborted, killed.
- Moves: submit, review, land, block, cancel. Stages: author,
  review, fix, ready, landed, blocked, canceled.
- Dimensions: `quest_type` (the plan: default is implemented;
  design, mvp, refactor, frontend, backend are proposed), `engine` (who executes: single,
  master-subagents, panes, workflows).
- Artifacts: QUEST.md, fsm.yaml, state.yaml, ledger.jsonl,
  tape.log, notes.md, experiments/, runs/.
- Ceremony lanes: micro, standard, high-blast-radius.

## Procedure

1. Name the kind of thing and where it will be read (CLI, file
   path, quest doc, chat). The same concept may need the kind's
   local spelling: kebab-case for slugs and files, lowercase
   words for verbs and stages.
2. Search the vocabulary above and the repo for the concept's
   existing word. If a word exists, use it, even imperfectly.
3. If no word exists, coin the shortest concrete one: a noun for
   things, a verb for moves. Two syllables beat three; a word a
   newcomer guesses correctly beats a clever one.
4. Check the name against its neighbors: it must not collide
   with, abbreviate, or synonym-shadow an existing term.
5. Say the name, the word it reuses or why none fit, and stop.

## Rules

- One concept, one word, one spelling, everywhere: files, CLI,
  docs, and chat. `canceled` in a status and `cancelled` in a
  stage is a bug, not a dialect.
- Concrete over abstract: prefer what the thing does or is
  (tape, ledger, submit) over machinery metaphors (flavor,
  harness adapter, pipeline stage) unless the metaphor is
  already the vocabulary.
- No new planning words. Task, Milestone, workflow, and graph
  terms stay out; Quest and exp are the planning vocabulary.
- Renames are explicit edits the human approves, with every
  reference updated in the same change. A rename that leaves a
  synonym behind in docs has not happened.
- Instructions only: this skill decides words, never state.
