---
status: frozen
date: 2026-11-11
promoted: null
---

# Pi engine (extract today's Pi launcher behind the engine contract)

## Context

Frozen during the red-ink walk of
[bp3-mvp-engine-core](../quests/2026-11-07-bp3-mvp-engine-core/QUEST.red-ink.md).
Exp 2 once carried two jobs: the new `bp3 q` CLI scaffold and
extracting today's Pi launcher behind a named engine contract
with zero behavior change. The owner threw the extraction out
of the core Quest: this Quest specifies the CLI, the FSM, and
the engine contract; engines are harness-specific bundles
built downstream. The Pi extraction is that downstream work.

What extraction meant, for the record: today's Pi launcher
(hardcoded Pi argv and Zellij calls, per Exp 2's old “fails
today”) moves behind the engine contract — context
provisioning (`cold | warm | fork | subagent`), Run dispatch,
tape capture, identity env — with zero behavior change for
the toy exps running on it.

## Sketch

- Wrap the existing Pi launcher as the first Pi-engine
  implementation of the settled contract: navigate the
  railway, dispatch small Runs, take transitions only through
  `bp3 q`, autoland, resolve blocked by bubbling to the
  human-facing session.
- Pi/Zellij argv exists only inside the Pi engine
  implementation; `bp3 context` (or its successor read) shows
  the provisioning mode per Run.
- Zero behavior change gate: a toy exp on today's Pi crew
  runs unchanged on the extracted engine. (The core Quest's
  Exp 1 baseline was killed — the owner ran Pi by hand and
  convicted it — so there is no measured phase breakdown to
  regress against; behavior identity is judged on the toy
  exp working the same, plus first-hand comparison.)

## Blockers

- **Core must exist first.** The CLI (`bp3 q`), the FSM
  binary, and the engine contract come from
  bp3-mvp-engine-core; there is nothing to extract behind
  until they land. The old `invoke` prototype is deleted and
  does not constrain this.
- **What “today's Pi launcher” is by then.** The launcher will
  have drifted; the thaw starts by re-reading its current
  shape, not this sketch.
- **Provisioning modes on Pi.** Which of `cold | warm | fork |
  subagent` Pi sessions can honestly provide, and which are
  emulated, needs evidence from the Pi executors quest.
- **Relationship to existing downstream quests.**
  [bp3 engine, Pi executors](../quests/2026-11-07-bp3-engine-pi.md)
  and [bp3 pi qol](../quests/2026-11-07-bp3-pi-qol.md) already
  exist; promotion must merge with them, not spawn a rival.
- **Tests that fail today.** No engine contract exists; Pi
  argv and Zellij calls are hardcoded in the launcher.

## Promotion trigger

Thaw when bp3-mvp-engine-core has landed (CLI + FSM +
contract real) and a Pi-run exp is wanted on the new core —
or when the Pi executors quest reaches the extraction step
and pulls this in.
