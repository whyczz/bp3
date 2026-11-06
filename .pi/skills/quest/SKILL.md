---
name: quest
description: Turn a known intent into a bp3 Quest file at docs/quests/<date>-<slug>.md with exps, acceptance checks, and human touchpoints.
---
<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Quest

Use when the user invokes this skill by name (`/quest`, `$quest`) or asks
to frame, spec, or start a new Quest in bp3. This skill is `design` applied to a Quest: it
proposes the Quest; it does not launch Workers, create Board records, or
land anything.

Use `ask` instead when the goal, user, or success test is still unclear.
Use `design` instead for a component design that is not a Quest.

## Procedure

1. Sync first. If the request is dictated or can be read two ways, run the
   iiuc playback and get a go before speccing the wrong Quest.
2. Research the actual ground: the MVP doc
   (`docs/designs/bp3-control-mvp.md`), the home repo's current state, and
   any prior Quest files under `docs/quests/`. Never spec against imagined
   state.
3. Ask only questions whose answers change the Quest's shape: home repo,
   success picture, lane, or the first exp. Everything else becomes an
   explicit assumption or an open question in the file.
4. Draft the file at `docs/quests/<date>-<slug>.md` in the Quest's home
   repo, where `<date>` is today as `YYYY-MM-DD` and `<slug>` is a short
   lowercase kebab-case summary of the goal. One Quest per file; exps live
   inside it, never as separate files.
5. Break the Quest into exps. Each exp gets an inspectable output and an
   acceptance check that fails today. A check that cannot fail is a hope,
   not an exp. Stage large exps as numbered substeps (1.1, 1.2, ...) when
   parts can pass independently.
6. Run the red-chair passes as you write, proportionately: attack the goal
   (is this the real ask, or a solution in disguise), the scope (what is
   cut and why it is safe to cut), and the exp order (is the riskiest
   useful slice first). Record the strongest attack and what it changed.

## File shape

```markdown
---
status: proposed | active | complete
home_repo: <repo>
date: <YYYY-MM-DD>
---

# <Quest name>

TL;DR
<what will be true when this Quest completes, and the one decision it makes>

ELI5
<the whole Quest in plain words, repeatable by a smart non-specialist>

## Goal and why
<the outcome pursued, in the user's words where possible>

## Success picture
<what the human will see, run, and judge at Quest-to-master; how completion
is recorded, with limitations stated>

## Scope
In: <...>
Out: <...>

## Human touchpoints
<framing, escalations, Quest-to-master promotion; everything else is
automated or it is listed here>

## Exps
### Exp 1 — <name>
- Intent: <bounded contribution>
- Lane: micro | standard | high-blast-radius
- Output: <inspectable artifact>
- Acceptance: <check that fails today, and its expected observation>
- Depends on: <prior exps, exact commits, or none>

## Scorecard
<what gets measured: human-active minutes, interventions, ceremony,
restarts, bypasses; where the numbers are recorded>

## Risks and red chair
<strongest attacks, what changed because of them, what remains open>

## Open questions
<ranked by what their answers would change, each with an owner>
```

## Rules

- The Quest file is the human-facing record; the Board is the runtime
  truth once implementation exists. Keep the file in sync at Quest gates,
  not after every exp event.
- Preserve the MVP vocabulary exactly: Quest, exp, execution, `auto_landed`,
  ceremony lanes, home repo. Do not introduce Task/Milestone or graph terms.
- Every exp's acceptance must be observable without reading transcripts or
  raw SQL.
- Quest files never claim implementation state that has not been observed:
  mark proposed checks as unmet, not as results.
- When the Quest is accepted and building starts, the accepted file
  governs; changes to goal or scope are explicit edits the human approves.
