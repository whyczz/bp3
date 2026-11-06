---
status: complete
home_repo: bp3
date: 2026-11-05
---

# bp3 skills install

TL;DR
bp3 gets a lightweight project-skills installer — `bp3 skills install
--harness=all` — and its first project skill, `/quest`. When this Quest
completes, any harness opened in bp3 can invoke `/quest` from a rendered,
validated skill whose source lives once in `skills/quest/`.

ELI5
Skills are instruction files that teach a coding agent a repeatable job.
bp3 keeps its own skills in the repo. This work writes the first one
(framing a Quest as a file), plus a small installer that copies it into
each harness's skill folder with the right invocation spelling, so the
same skill works in pi, Claude, Codex, and Muse.

## Goal and why

The Controller and Workers in bp3 will run skills that only make sense
inside this repo. Those skills need one authoring source and a boring way
to reach every harness without copying a renderer/installer toolchain
from bp3-yap-skills. The first skill is `/quest` itself: if the Quest
format can't describe this Quest, the format is wrong.

## Success picture

From a fresh shell in bp3: `./bin/bp3 skills install --harness=all`
renders `quest` into `.pi/skills/`, `.claude/skills/`, and
`.agents/skills/`; `muse skills validate .agents/skills/quest --json`
reports `valid: true`; the MVP doc states the convention; and this file
is the human record. Completion is recorded here with limitations, not
laundered into the Board (which does not exist yet).

## Scope

In: quest skill source, bash installer, rendered outputs, MVP doc
convention, this Quest file.
Out: the OCaml `bp3` CLI absorbing the installer, Board records or
`quest activate`, Board-coupled control skills (packet, Controller loop),
moving `/quest` into bp3-yap-skills.

## Human touchpoints

Framing (done in conversation), acceptance of this Quest file, and the
commit/push decision. No Worker or Board exists yet; the human is the
scheduler for this Quest, which is the condition Quest 1 of the MVP
exists to remove.

## Exps

Each exp is tiny: one output, one check, minutes not hours.

### Exp 1 — Quest skill source

- Intent: author `/quest` once, harness-neutrally.
- Lane: micro
- Output: `skills/quest/SKILL.md` with a `{{ invocation }}` placeholder,
  shaped like the `design` skill.
- Acceptance: no harness-specific spelling outside the placeholder.
  Observed: done.
- Depends on: none

### Exp 2 — Installer renders one harness

- Intent: prove render-and-copy works at all.
- Lane: micro
- Output: `bin/bp3 skills install --harness=muse`; rendered
  `.agents/skills/quest/SKILL.md` with GENERATED notice after frontmatter.
- Acceptance: `muse skills validate .agents/skills/quest --json` reports
  `valid: true`, zero diagnostics. Observed: done.
- Depends on: Exp 1

### Exp 3 — Installer renders all harnesses

- Intent: prove per-harness invocation spellings from the one source.
- Lane: micro
- Output: `--harness=all` renders into `.pi/skills/`, `.claude/skills/`,
  and `.agents/skills/` (codex and muse share the last dir; muse written
  last, only the trigger line differs).
- Acceptance: all three dirs hold `quest/SKILL.md` with the correct
  spelling for their harness. Observed: done.
- Depends on: Exp 2

### Exp 4 — Convention in the MVP doc, this file as first instance

- Intent: make the pattern a rule of working in bp3, not chat folklore.
- Lane: micro
- Output: MVP Repository shape section states source location, installer
  command, spellings, generated-file rule, and the
  `docs/quests/<date>-<slug>.md` convention; this file exists as instance
  one.
- Acceptance: both statements present in
  `docs/designs/bp3-control-mvp.md`. Observed: done.
- Depends on: Exp 3

### Exp 5 — Land this Quest

- Intent: commit and push everything above plus Quest 2's file.
- Lane: micro
- Output: commit(s) on `main` in `whyczz/bp3`.
- Acceptance: `git status` clean after push. Observed: done — landed in
  `4467ab6` and pushed; follow-up gatekeepers landed in `b72b97b`.
- Depends on: Exp 1-4

## Scorecard

Human-active minutes and interventions are the only metrics that exist
pre-Board; both were one conversation. Ceremony judgment: one bash script
(~70 lines) instead of a ported renderer — proportionate. No restarts, no
bypasses.

## Risks and red chair

Strongest attack: a bash installer becomes a second toolchain to maintain
beside bp3-yap-skills. Mitigation: it renders exactly one placeholder and
is explicitly pre-binary scaffolding the OCaml CLI absorbs later.
Second attack: rendered duplicates drift from source. Mitigation:
GENERATED notice plus edit-source-and-re-run rule. Remaining risk: codex
and muse share `.agents/skills`, so `--harness=all` writes that dir twice
(muse last); only the trigger line differs and both accept the skill by
name.

## Open questions

- When the OCaml CLI lands, does `bp3 skills install` keep the bash
  script's exact interface? Owner: implementer. Recommended: yes.
- Do rendered skill dirs get committed or gitignored? Owner: human, at
  Exp 5. Recommended: commit them, so a fresh clone has working skills
  before anyone runs an installer.
