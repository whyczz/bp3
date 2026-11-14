---
name: icebox
description: Freeze a not-yet-ready idea as a future-quest sketch in docs/icebox with today's context, the smallest workable shape, blockers, and a promotion trigger.
---

# Icebox

Use when a human in bp3 says to icebox, freeze, or park an idea
for a future quest (`/icebox`), or when a design session settles
a direction but deliberately defers it past the current quest.
One output: one entry in `docs/icebox/` that a later `/quest`
can promote by transcription.

Use `quest` instead when the idea is ready to frame now.
Use `add-bp3-skill` or `add-yap-skill` when the idea is a skill.
Use `red-ink` when an existing design needs a decision walk.

## Procedure

1. Capture today's context first: what was being designed, the
   decision just settled or deferred, and links to the files
   that hold it. Context is written for a reader who was not
   in the session.
2. Sketch the smallest version that would work: states, edges,
   commands, or files it touches — and what it deliberately
   does not add.
3. List every blocker already known: missing facts, undecided
   questions, dependencies, identity/data gaps, tests that
   would fail today. “None known” is a claim; make it honestly.
4. Name the promotion trigger: the observable signal that says
   thaw this now. No trigger, no entry — an idea that can never
   ripen is a note, not an icebox entry.
5. Write `docs/icebox/YYYY-MM-DD-<slug>.md` (today's date,
   short kebab slug, chosen with `naming` if the slug is not
   obvious) with frontmatter `status: frozen`, `date`, and
   `promoted: null`, and sections Context, Sketch, Blockers,
   Promotion trigger, matching `docs/icebox/README.md`.
6. If the idea was deferred inside a live design, record the
   deferral where the design lives (one line: deferred to the
   icebox entry, with its path). The design keeps no shadow
   version of the frozen sketch.

## Rules

- An icebox entry is not a quest, not state, and never a
  decision record. It freezes a sketch; promotion re-decides
  anything the entry merely assumed.
- Quick means quick: one short file. If the sketch needs exp
  breakdowns and acceptance checks, it is ready for `/quest`.
- Never delete an entry. On promotion, set `promoted:` to the
  quest path and leave the entry as the fossil record.
- Instructions only: this skill writes docs. It creates no
  branches, ledger lines, or Board records.
