---
name: add-yap-skill
description: "Add a portable, human-invoked skill to bp3-yap-skills through its gates: clarify, prior art, red chair, and trigger tests."
---
<!-- GENERATED from skills/add-yap-skill/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Add Yap Skill

Use when the user invokes this skill by name (`/add-yap-skill`) or asks
to add a skill to bp3-yap-skills. This is the yap roster's gatekeeper, renamed so it can
live beside bp3 project skills without colliding with any global
`add-skill`. It writes nothing until every gate passes; failing a gate
produces a report, not a directory. Absorb-or-reject is the common
outcome.

Target repo: bp3-yap-skills (the personal, portable skill library).
Anything needing Board state, tool blocking, hooks, or runtime code does
not belong there — route it to an add-bp3-skill proposal instead.

## Gates, in order

1. Clarify. Use iiuc/ask discipline. The candidate gets: a one-sentence
   job, a human invoker by name, three example invocations, and three
   near-miss invocations that must not trigger it. No examples, no
   further gates. A candidate with no papercut, session, or repeated
   correction behind it stops here.
2. Search prior art. In order: the yap roster, bp2's catalog, bp1's
   workflow skills, then the internet (Superpowers, Compound
   Engineering, gstack, Anthropic's skills, a web search for the job in
   words). Output: a list of existing skill, overlap, absorb-or-not. If
   an existing skill absorbs it with a section added, the result is that
   edit, not a new skill.
3. Mine the logs (optional). When an archive miner exists, ask it for
   sessions for and against the candidate. Every claim needs session
   links and counts. No archive means this gate is `unchecked`, recorded
   as such — never as support, never as a blocker.
4. Red chair. Read-only adversarial pass: overlap stated plainly; the
   stateless test (any Board, queue, hook, or daemon need routes it out
   of yap, by name); failure modes; context tax on every future session;
   name collisions across harnesses. Verdict: absorb, reject, or proceed.
5. Adversarial checks. The three examples must trigger the candidate,
   the three near-misses must not, plus two hostile cases (keyword match
   that wants a different skill; stateful work wearing yap words). Test
   against a draft in a scratch session; keep the transcripts.
6. Write, only now. In bp3-yap-skills: scaffold with `yap new <id>`,
   replace every TODO, add the README roster row, pass
   `dune build @render` and `dune test`. Record beside the change: the
   search results, mined evidence where it exists, chair verdict, and
   test transcripts.

## Rules

- The user is the final gate. An overruled chair verdict is recorded
  with their reason.
- One skill, one job, invocable by a human by name, one specified output
  shape. Anything else is a worker pack or a control skill; route it,
  do not force it in.
- Never edit an existing skill silently as a side effect. Absorption is
  a named edit the user sees.
- This skill lives in bp3 as a project skill; the work it gates lands in
  bp3-yap-skills. Do not create the new skill inside bp3 by accident.
