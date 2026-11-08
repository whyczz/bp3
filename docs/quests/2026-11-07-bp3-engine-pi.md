---
status: proposed
home_repo: bp3
date: 2026-11-07
---

# bp3 engine, Pi executors: oh-my-pi, extensions, or our own

TL;DR
The engine concepts get a Pi executor. Three candidates compete on
evidence — oh-my-pi's built-in subagents, the leading Pi subagent
extension, and rolling our own — judged on honest settled/idle
signals, generation fencing, and context cost per edge. When this
Quest lands, Pi takes commit-state edges through the same machine
Muse workflows proved, on the winning subagent system.

ELI5
We already have the baton (a clean commit) and the rules of the
game. Now we try three kinds of Pi players and keep score: the
all-in-one fork, the popular add-on, and a home-made minimal one.
Fastest honest player wins; lying about being finished loses.

## Goal and why

The [engine MVP Quest](2026-11-07-bp3-mvp-engine.md) proves the
commit-state FSM with Muse workflows as first executor. Pi is
where the human already lives day to day, and the
[Pi basics dossier](../dossiers/bp3-pi-basics.md) shows the
subagent field is crowded and fast-moving: oh-my-pi (hard fork,
first-class `task` tool, parked-agent revival), in-process Pi
subagent extensions (fast, cache-aware), and process-per-child
designs (full context rent). bp3's bridge contract — `settled`
only when truly idle, stale generations fenced — is unproven
against all of them. This Quest investigates, experiments, and
decides build versus borrow with fixture evidence, including the
honest option: roll a minimal subagent system of our own shaped
exactly to the edge contract.

## Success picture

The toy exp travels author → review → land on Pi with the chosen
subagent system; a commit-state produced by a Muse workflow
child is picked up by a Pi executor unchanged (and vice versa);
context cost per edge is recorded against the engine baseline.
The build-versus-borrow verdict is written with what would
reverse it.

## Scope

In: oh-my-pi evaluation, subagent-extension evaluation, a
build-our-own investigation with a working minimal prototype if
the borrow options fail, honesty/fencing fixtures, and executor
interchange with the Muse test. Sibling:
[Pi quality of life Quest](2026-11-07-bp3-pi-basics.md) owns the
general Pi speed meta; this Quest owns only the subagent system.
Out: adopting a fork wholesale without the verdict, general
extension curation, and bridge contract changes (engine Quest).

## Human touchpoints

Quest framing, the build-versus-borrow verdict, fork adoption if
proposed, escalations, and Quest-to-master promotion.

## Exps

### Exp 1 — oh-my-pi as executor

- Intent: price the all-in-one fork honestly.
- Lane: standard
- Output: toy exp edges taken via omp's `task` tool (shared
  context, isolated worktrees, parked-agent revival), with its
  advisor/review roles noted; tool-surface and cache costs
  measured against bare Pi.
- Acceptance: edges complete with honest idle (no settled during
  in-flight work); revival by message beats respawn on cost, or
  the claim is falsified with numbers. Fails today: omp never run
  under bp3; launcher pins Pi bare.
- Depends on: engine MVP Quest Exps 2–3 (seam, FSM).

### Exp 2 — Subagent extension as executor

- Intent: price the borrow option on vanilla Pi.
- Lane: standard
- Output: toy exp edges taken via the leading in-process subagents
  extension (pinned version, lazy loading), scout/author/reviewer
  children reporting through Board ops.
- Acceptance: toy green with fan-out; prompt cache survives child
  loading; stale-generation child report rejected. Fails today:
  no extension installed; `--no-extensions` is the law.
- Depends on: engine MVP Quest Exps 2–3.

### Exp 3 — Build versus borrow: our own minimal subagent system

- Intent: decide with a prototype, not opinions.
- Lane: standard
- Output: failure/cost ledger for Exps 1–2 (honesty failures,
  cache damage, maintenance surface, fork drift), plus — if
  either borrow fails a guard — a minimal own system: spawn child
  session, hand it a commit-state, collect one edge result,
  nothing else. Scored on the same fixture.
- Acceptance: a written verdict (borrow X / adopt omp / build
  ours) with per-candidate guard results and what would reverse
  it. Fails today: no candidate has run; "roll our own" is a
  hunch.
- Depends on: Exps 1 and 2.

### Exp 4 — Pi executor lands in the machine

- Intent: make the winner a real executor, interchangeable with
  Muse.
- Lane: standard
- Output: the winning system wired behind the engine contract;
  the interchange test (Muse-authored commit-state reviewed by
  Pi, Pi-authored reviewed by Muse); one real bp3 exp traveled
  end to end on Pi.
- Acceptance: interchange passes with identical guards; the real
  exp lands with its report; cost per edge recorded. Fails
  today: no Pi executor exists.
- Depends on: Exp 3; engine MVP Quest Exp 4 (Muse test states).

## Scorecard

Per candidate: honesty failures (target zero), tokens and wall
time per edge, cache damage, lines of integration code, and
maintenance surface. Recorded here and in exp records; vendor
claims are stated as claims until a fixture confirms them.

## Risks and red chair

- Strongest attack: three-way bake-offs are how weekends die.
  What changed: one toy fixture, four exps, kill criteria per
  candidate (any honesty failure is out, regardless of speed).
- Strongest attack: rolling our own repeats everyone else's bugs.
  What changed: own-system scope is one edge wide by design; it
  exists only if borrows fail guards, and Exp 3 must show the
  failure first.
- Remaining open: fork drift if omp wins — its upstream merge
  cadence becomes bp3's tax; the verdict must price it.

## Open questions

1. Build versus borrow — settled by Exp 3 evidence, not taste.
   Owner: human, on the Exp 3 ledger.
2. If omp wins, do we track upstream or pin and drift? Default:
   pin, re-evaluate quarterly. Owner: human.
3. Does the winner change the bridge, or live behind it? Default:
   behind the existing contract; contract changes belong to the
   engine Quest. Owner: implementer.
