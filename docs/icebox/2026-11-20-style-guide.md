---
status: frozen
date: 2026-11-20
promoted: null
---

# STYLE.md: how bp3 code reads, written down

## Context

Frozen 2026-11-20, at approval of the constraints-context quest
(`docs/quests/2026-11-19-constraints-context/`). The owner's canon
memo (2026-11-19) named style guides among the pre-LLM gems worth
reusing: "writing tests, organizing code in in a way, having style
guides". The quest asked where a style guide lives (its open
question 2); the owner's call was to icebox it.

What exists today: CONSTRAINTS.md (rules.1) says what bp3 may be
built from, not how the code should read. CONTEXT.md's canon
section (ctx.1) records the principle with its filter verdict, not
bp3's rules. shellcheck and `node --check` run in `make lint`;
there is no `.ocamlformat`.

## Sketch

- `STYLE.md` at the repo root, one page, linked from CLAUDE.md and
  AGENTS.md next to CONSTRAINTS.md and CONTEXT.md.
- Only rules no existing lint checks. Each rule is one line with
  its source: a canon entry in CONTEXT.md, or a dated bp3 lesson.
- Candidates: names follow the code's existing spelling; an error
  message names the fix (CONTEXT.md labs section); one idea per
  commit; comments match the density of the code around them.
- Deliberately not added: a formatter config, a rule engine
  (`docs/icebox/2026-11-15-bp3-lint.md` stays frozen), new lint
  steps.

## Blockers

- Which rules are actually broken today? No grader or red-ink round
  has flagged style twice yet, so the list would be guesswork.
- Overlap with CONTEXT.md's canon section: a rule there and here
  must not say the same thing twice.
- Whether `ocamlformat` should come first. That is a new tool, so it
  needs a sign-off row in CONSTRAINTS.md.

## Promotion trigger

A grader or red-ink round flags the same style issue in two
different quests, or the owner names this entry.
