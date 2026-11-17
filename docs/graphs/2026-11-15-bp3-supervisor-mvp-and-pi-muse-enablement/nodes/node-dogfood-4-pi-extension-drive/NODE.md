---
date: 2026-11-16
goal: ../GRAPH.md
exp: dogfood.4
status: proposed
---

# dogfood.4 - pi-extension-drive: flappy driven from pi, through the extension

## TL;DR

Dogfood the implemented pi engine: a pi conductor
session with `bp3-pi` loaded drives the toy work
through its own tools — `spawn_run` an author child
to build the flappy demo, `await_runs` to settle it,
`list_runs` showing the supervisor's derivation. The
muse author of dogfood.3 played launcher by hand;
here the extension is the launcher.

## Demo (design trace)

```text
pi conductor (bp3-pi loaded)
  spawn_run(author) ─► pi child builds flappy.html in its run folder
  await_runs ─► settled; supervisor fold: finished
  list_runs ─► finished, warnings []
artifact served; node --check passes
```

## Diagram

```text
pi conductor ──spawn_run──► pi author child ─► flappy.html
      │ await_runs (watch)        │ tape
      ▼                           ▼
   settled              supervisor fold ─► finished
```

## Pseudocode

```python
run = spawn_run(role="author", prompt=build_flappy)
assert await_runs([run]) == settled
assert list_runs()[run].lifecycle == "finished"
assert artifact_ok("flappy.html")
```

| Field | Value |
|---|---|
| Intent | the pi engine drives real work with no hand-played launcher |
| Lane | standard |
| Output | flappy demo built by an extension-spawned pi child; derivations |
| Depends on | followup.5, followup.6 |

## Acceptance

| Case | Expected |
|---|---|
| extension drive | pi conductor spawns the author child via `spawn_run` only; no shell-spawned pi, no hand-called record-init/bind-tape in the drive (drive trace) |
| supervised finish | supervisor derives the author Run `finished` from its tape; `await_runs` reports settled from watch |
| demo artifact | `flappy.html` in the author Run's folder, built by the pi child; `node --check` passes on its extracted module |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment for both Runs and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the pi engine, as implemented,
  drives the toy end to end under supervision.
- **Prove by:** the drive trace, the `finished`
  derivation, and the artifact.
- **Done when:** extension-spawned pi child built
  the demo and derived `finished`, observed.

## Tests

Full drive observed once, clean. Artifact smoke:
`node --check` on the extracted module. Serve the
artifact alongside dogfood.1/.3's for the owner's
harness comparison. Known non-cases: no nested
quest/induct drive (owner ruled out of scope); the
child does demo work, not bp3 state moves.

## Context

dogfood.3 was the same drive with the launcher
played by hand from muse. One variable changes:
the launcher is now the product under test.
