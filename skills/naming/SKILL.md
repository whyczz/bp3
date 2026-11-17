---
name: naming
description: "Choose concrete, short names in bp3's existing vocabulary for graphs, nodes, skills, plans, engines, and CLI verbs."
---

# Naming

Use when a human, Controller, or Worker in bp3 must name or
rename something: a graph slug, node, skill, plan (`goal_type`),
engine, CLI verb, file, or state. Invoked by name (`/naming`,
`$naming`). One output: one recommended name, with the vocabulary
it reuses. A shortlist only when two names genuinely tie.

Use `bp3g-frame` for framing a graph (it delegates naming here),
`using-bp3` for operating the CLI, and general judgment for
ordinary code identifiers with no bp3 meaning.

## The vocabulary (reuse before inventing)

- Planning: graph, node, Run. The conducting skill family is
  `bp3g`: `/bp3g` conducts a graph, `/bp3g-frame` frames one,
  `/bp3g-no-human` runs unattended (G stands for goal and graph;
  bare "goal" collides across harnesses).
- Doors: `bp3 g` (graph), `bp3 n` (claimed node), `bp3 e`
  (claimed edge); the canonical address nests:
  `bp3 g <graph> n <node> e <edge>`. One door per noun; the
  retired `bp3 q` door refuses.
- Node states (where a node rests): todo, handed_off, approved,
  landed, blocked, deleted. Graph lifecycle: proposed, active,
  landed, canceled. Never archived, cancelled, aborted, killed.
- Edges (one transition, executed by exactly one Run):
  handoff, grade, verify, land, block, resume. A dep links
  nodes; a dep is not an edge. Stages: author, grade, fix,
  ready, landed, blocked, canceled.
- Goal and graph: the container of work is a **goal** (`docs/graphs/<goal>/GRAPH.md`, `goal/<slug>` branch, finish word `goal_fin`); its DAG of nodes is the **graph** (`bp3 g` unchanged). Graph id/slug unchanged by the goal rename.
- Dimensions: `goal_type` (the plan: default is implemented;
  design, mvp, refactor, frontend, backend are proposed), `engine` (who executes: single,
  master-subagents, panes, workflows).
- Artifacts: GRAPH.md, state.yaml, ledger.jsonl,
  tape.log, notes.md, runs/. Storage paths and ledger history
  keep their frozen spellings (landed ledger text, `bp3/quest/` legacy refs, `quest_type` legacy key); only the fold maps them.
- Ceremony lanes: micro, standard, high-blast-radius.

## Procedure

1. Name the kind of thing and where it will be read (CLI, file
   path, graph doc, chat). The same concept may need the kind's
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
  (tape, ledger, handoff) over machinery metaphors (flavor,
  harness adapter, pipeline stage) unless the metaphor is
  already the vocabulary.
- No new planning words. Task, Milestone, and workflow
  terms stay out; graph and node are the planning vocabulary.
  The retired pre-rename spellings for graph and node live
  only in frozen history and the fold's compat mapping.
- Renames are explicit edits the human approves, with every
  reference updated in the same change. A rename that leaves a
  synonym behind in docs has not happened.
- Instructions only: this skill decides words, never state.
