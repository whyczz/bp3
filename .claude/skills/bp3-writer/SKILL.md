---
name: bp3-writer
description: "Write or update a bp3 exp record at docs/exp/<date>-<slug>.md: TL;DR, mini-design, code tour, acceptance evidence, runbook, and next steps."
---
<!-- GENERATED from skills/bp3-writer/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# BP3 writer

Use when invoked by name (`/bp3-writer`, `$bp3-writer`) or when a human,
Controller, or Worker asks to document a specific bp3 exp,
turn its code walkthrough into a durable report, or consolidate its design and
execution evidence. One output: the exp's canonical Markdown record.

Use `quest` for framing the parent pursuit, `design` for a general proposed
architecture, and `tldr` for a read-only chat primer. A generic style rewrite
alone is not a bp3-writer task. This skill does not launch work or mutate Boards.

## Procedure

1. Identify the parent Quest, exp, and source revision. Read the Quest, existing
   exp record, actual changed code and tests, and available acceptance receipts.
   Ask only if missing identity or scope changes which record should be written.
2. Use `docs/exp/YYYY-MM-DD-short-kebab-slug.md` in the home repo. Reuse the
   existing record and original date; when migrating, retain the documented
   exp/Quest origin date rather than inventing a fresh execution date. One
   canonical record per exp, not parallel design/runbook/report copies.
3. Lead with a short TL;DR and explicit implementation status. Walk the system
   by responsibility, not file enumeration. For each substantial section give:
   purpose, data/types, key functions and flow, invariants/failure behavior,
   and linked code pointers. Explain before/after behavior with one real trace.
4. Separate intended acceptance from observed evidence. Bind observations to
   commits, commands and receipts; retain failed attempts and limitations.
   Say not run/unverified when appropriate. Invoke `verify` before producing
   new passing claims; do not rerun paid/live drills merely to rewrite prose.
5. Include reproducible checks, human touchpoints, recovery/rollback boundaries,
   and the next unresolved step. Preserve useful runbook detail beneath the
   short overview. Never include credentials, raw authenticated receipts, or
   fabricated costs/approvals.
6. Link the record from the parent Quest and README where useful. The Quest
   keeps intent, ordering, dependencies and concise acceptance status; link
   details rather than making another competing source. Fix relative links,
   CLI help references and callers after moves. Keep cross-exp architecture
   in `docs/designs/`. Retire superseded files; do not leave two live contracts.
7. Check frontmatter, paths/anchors, factual consistency and the distinction
   between proposed, implemented, tested, accepted, landed and promoted.

## File shape

Frontmatter: `date` (YYYY-MM-DD), `quest` (relative link to the parent file),
`exp` (the parent's identifier), `status` (`proposed`, `active`, or `complete`).
Completion refers to that exp's acceptance, not implicit landing/promotion.

Body: title; TL;DR/ELI5; context and scope; mini-design and code tour; acceptance
and evidence; runbook/recovery; risks and next steps. Scale the depth to the
change. Keep source revisions and historical receipts explicit.

## Composition with anon-writer

When requested together, read the actual `anon-writer` skill from its available
location first. If it is unavailable, ask for its source; do not claim to have
applied it, copy it into this skill, or silently install another project's skill.

BP3 writer owns the path, metadata, required technical content and evidence
boundaries. Anon-writer owns voice, concision, coaching, humor and presentation.
Its OODA organization fits naturally: Observe = context/evidence; Orient =
mini-design/code tour; Decide = decisions/risks; Act = checks/recovery/next steps.
Use that mapping rather than duplicating both outlines. Types, small ASCII
flows and OCaml/Python pseudocode are useful when grounded in the real code.
Humor must not replace technical content or turn a proposal into a fact.

## Rules

- Instructions only: no skill-private state, hooks, daemon assumptions or Board
  writes. Reading a snapshot does not authorize changing it.
- Report what exists. A candidate is not approval; idle is not completion;
  transport observation is not answer handling. Use the bp3 vocabulary exactly.
- Use `master` for the integration branch; preserve Quest-branch separation.
- Do not silently expand scope, approve work, commit, promote or push.
- Do not require anon-writer for factual documentation when it was not requested.
