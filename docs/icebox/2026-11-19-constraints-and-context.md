---
status: frozen
date: 2026-11-19
promoted: null
---

# CONSTRAINTS.md and CONTEXT.md: plans and reviews check against them

## Context

Frozen 2026-11-19, mid-run of the test-pyramid quest
(`docs/quests/2026-11-18-test-pyramid/`). Owner, verbatim:

> the reviewer, /quest planning goes thru our CONSTRAINTS.md ->
> a. one constraint is the languages used, we should not add one
> unless it brings alot of value. here "brings alot of value" is a
> human decision, like I need to sign off, you need to convice,
> /teach me.
> b. surfaces, like bp3 is a CLI. we're not building a web app, etc
> unless it /quest'd out, e.g. brings value
> c. a common sense pass, like a /red-chair on /red-ink , but I feel
> like we're making strange decisions. for example doing research on
> how other people build their agent systems gives us ground for
> common sense. we should have that in a CONTEXT.md

What prompted it:

- Node tier.1 (the suite runner) was written in bash 3.2. perl
  one-liners filled three gaps: process groups, a millisecond clock,
  and resetting an ignored SIGINT. No plan, red-ink round, or grader
  asked whether the runner should use another language. It took six
  grading rounds, most of them on bash job-control and signal edge
  cases. It was rewritten in OCaml (d6a711f on
  `quest/2026-11-18-test-pyramid`) only after the owner asked "why
  can't we use ocaml for this?".
- Graders judged each commit against its NODE.md gates only. They
  found real signal bugs but could not flag the language choice,
  because nothing written forbids it.
- Language census on the quest branch today:
  - OCaml: the engine and the runner.
  - bash: `bin/bp3` and 27+ test scripts.
  - JS/TS: the pi extension, workflows and node:test.
  - python: the pty driver embedded in `test/run-suites.sh`.
  - perl: one-liners in 14 test files (the `max_cycles: 1` pin).

  A census by file extension shows only the first three; python and
  perl live in heredocs and `-e` strings.
- Research ground is thin: `docs/dossiers/` has two dossiers
  (`bp3-pi-basics.md`, `muse-workflows-hooks.md`), and none on how
  other teams build agent systems.

## Sketch

Two short root files, read by planning and review, plus a check in
each place a plan or commit is judged.

```text
CONSTRAINTS.md (owner-signed rules) ──┐
CONTEXT.md (common-sense ground) ─────┤
                                      ▼
/quest step 2 research ── reads both
/quest step 7 red chair ── constraints pass + common-sense pass
grader brief ─── commit adds language/surface/dep outside CONSTRAINTS?
                   -> needs_fix, class owner (pages the human)
change a constraint ── /teach pitch -> owner signs -> dated row
```

- **CONSTRAINTS.md**: one row per rule, giving the rule, why it
  holds, and how to change it. First rows:
  - **Languages:** OCaml for the engine and tools; bash for thin
    wrappers only; JS/TS inside the pi extension and workflows only.
    Adding a language, including an embedded one (heredoc python,
    perl `-e`), needs the owner's sign-off after a `/teach` pitch.
  - **Surfaces:** bp3 is a CLI, plus skills and harness extensions. No
    web app, daemon or service unless a quest frames it and the owner
    approves.
  - **Dependencies:** OCaml stdlib, `unix`, yojson, str (tests: ounit2,
    qcheck), and the Brewfile tools. A new one goes through the same
    sign-off.
- **Sign-off record**: every change to a constraint adds a dated row
  with the owner's words, so the file explains itself.
- **CONTEXT.md**: common-sense ground, meaning how other agent and
  dev-tool systems solve the problems bp3 meets (runners, state,
  review loops, sandboxes). Each claim is linked to a source or
  dossier and dated. bp3's own lessons sit beside it, for example "a
  shell is the wrong place for signal-heavy process control"
  (tier.1).
- **Common-sense pass**: a red-chair lens, "how would another team
  build this, and why are we different?", answered from CONTEXT.md.
  It runs in `/quest` step 7 and at red-ink settle.

Not added: engine state, ledger fields, or automatic blocking. This
is docs plus skill text. A mechanical lint is optional (see
Blockers).

## Blockers

- **Location:** repo root, next to CLAUDE.md and AGENTS.md, or
  `docs/`? And should the harness files link them so every session
  loads them?
- **What counts as a language:** bash glue, jq/yq filters, awk,
  `python3 -` heredocs. A definition is needed before any check can
  be fair.
- **Existing violations:** python in `test/run-suites.sh`, perl in 14
  test files, and JS/TS. Grandfather them as dated rows, or retire
  them (possibly inside test-pyramid's retire.1)? This is the owner's
  call.
- **Enforcement:** prose rules in skills, or a lint in `make check`
  that scans shebangs, heredoc interpreters and `-e` one-liners?
  The lint overlaps `2026-11-15-bp3-lint.md`; pick one home.
- **CONTEXT.md research:** which systems to cover, who runs it (the
  `dossier` skill fits), and how stale claims get re-checked. No
  claims are written until the research runs.
- **Skill changes ride as their own nodes:** quest (steps 2 and 7),
  red-ink (settle), red-chair (new lens), and the grader briefs in
  `induct-inline` and `induct-grade`.
- **Overlap with `2026-11-19-yolo-decider.md`:** a constraints
  finding must never be classed `yolo` or `mechanical`. It always
  pages the owner.

## Promotion trigger

The test-pyramid quest lands, or earlier if any plan or commit adds a
language, surface or dependency before then.
