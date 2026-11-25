---
name: icebox
description: Freeze a not-yet-ready idea as a future-quest sketch in docs/icebox with today's context, the smallest workable shape, blockers, and a promotion trigger.
---
<!-- GENERATED from skills/icebox/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

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

0. **Clean-runway guard:** before writing any file, check the current
   branch. If already inside a non-master worktree (`quest/*` or
   `draft/*`), proceed directly. If on `master`/`main`, run
   `bp3 harness desk list` and inspect `target_dirty`:
   - `target_dirty == false`: write the entry and **commit immediately**
     on `master` in the same turn (0s dirty window; parallel quests
     merge cleanly over `docs/icebox/` drift via CAS `merge-tree`).
   - `target_dirty == true`: run
     `bp3 harness desk prepare --draft icebox-<slug>`, write and commit
     there, and land with `bp3 harness desk land --draft icebox-<slug>`
     once `master` is clean.
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

## Promotion (receiving end)

Promotion is defined in the `quest` skill (section
"Promotion from the icebox"): trigger fires, owner names the
entry, the Quest procedure re-decides everything, and at
owner approval the entry is copied verbatim to `ICEBOX.md`
in the Quest folder, gains a `promoted:` field pointing
at the Quest, and is then **deleted** — git history is the
fossil. This skill never edits an entry beyond that field
before the delete.

## Rules

- An icebox entry is not a quest, not state, and never a
  decision record. It freezes a sketch; promotion re-decides
  anything the entry merely assumed.
- Quick means quick: one short file. If the sketch needs node
  breakdowns and acceptance checks, it is ready for `/quest`.
- On promotion, set `promoted:` to the quest path, then
  delete the entry (owner rule, 2026-11-15). Git history is
  the fossil record; an unpromoted entry is never deleted.
- Whenever a `/quest` or `/quest` is written from an entry,
  copy the entry **verbatim** to `ICEBOX.md` in the
  quest/quest folder before any delete — never transcribed
  into prose (owner rule, 2026-11-17).
- Instructions only: this skill writes docs (and commits cleanly per
  the clean-runway guard). It creates no ledger lines or Board records.
