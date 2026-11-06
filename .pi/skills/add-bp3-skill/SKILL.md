---
name: add-bp3-skill
description: Add a bp3 project skill under skills/ and install it per project with bp3 skills install, through overlap, statelessness, and trigger checks.
---
<!-- GENERATED from skills/add-bp3-skill/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Add BP3 Skill

Use when the user invokes this skill by name (`/add-bp3-skill`) or asks
to add a skill to bp3 itself. Project skills live in this repo, load only inside bp3, and
version with the code. This skill is the bp3-side gatekeeper; it writes
nothing until the checks pass.

Use add-yap-skill instead when the skill
is portable, stateless, and human-invoked across projects. If it could
work unchanged in esc3 or any other repo, it is a yap skill wearing bp3
clothes — route it there.

## Procedure

1. Clarify the job in one sentence: who invokes it (human, Controller,
   or Worker), in which repo context, and the one output shape it
   produces. Three example invocations and three near-misses that must
   not trigger it. No examples, no write.
2. Check overlap. Search bp3's `skills/`, the MVP doc, and the yap
   roster. If an existing skill absorbs the job with a section added,
   propose that edit instead. If the job is portable and stateless,
   stop and route to add-yap-skill.
3. Run the stateless test in reverse: project skills may touch bp3
   concepts (Quest files, Board ops, lanes), but the skill file itself
   stays instructions — no state, no hooks, no daemon assumptions.
   Anything needing runtime behavior belongs in core, not a skill.
4. Red chair, proportionate: wrong layer (core vs skill vs yap),
   context tax on Controller/Worker sessions that will load it, name
   collisions with yap skills across harnesses, and trigger overlap
   with quest/add-yap-skill.
5. Write the source at `skills/<skill-id>/SKILL.md`: frontmatter `name`
   equal to the directory, one-sentence `description`, no template placeholders, concise self-contained
   body in the house shape (when to use, procedure, rules).
6. Install and verify: run `./bin/bp3 skills install --harness=all`,
   then `muse skills validate .agents/skills/<skill-id> --json` must
   report `valid: true` with zero diagnostics. Confirm the render in
   each harness dir carries that harness's invocation spelling.
7. Report: source path, rendered paths, validator result, and what was
   not verified (other harnesses' live loading is observed, not assumed).

## Rules

- One skill, one job, one output shape. Bundled "and also" jobs split
  or stop.
- Sources are edited; rendered files under `.pi/`, `.claude/`, and
  `.agents/` are generated — never hand-edit a render.
- No TODO text in a shipped source; an unfinished skill is a draft
  outside `skills/`.
- Committing is the human's call, as with every bp3 change; this skill
  never commits or pushes.
- Keep the body short enough to load in a Worker brief's budget. A
  project skill that needs a manual has the wrong shape.
