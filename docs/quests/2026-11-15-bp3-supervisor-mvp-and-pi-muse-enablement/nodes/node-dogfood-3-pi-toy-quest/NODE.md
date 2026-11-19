---
date: 2026-11-15
goal: ../QUEST.md
exp: dogfood.3
status: proposed
---

# dogfood.3 - pi-toy-quest: flappy bird on pi, supervised

## TL;DR

dogfood.1's toy demo, produced by a pi experiment Run
under the supervisor: one pi child builds the flappy
demo, the supervisor derives that Run's lifecycle from
the pi tape. No full pi toy-quest drive, no nested
induct (owner ruling: demos are experiment Runs, not
full inducts; nested quests are out of scope).

## Demo (design trace)

```text
author (muse-code) ─► spawns pi child (experiment Run)
pi child ─► flappy.html in its run folder, exits
supervisor ─► derives pi Run finished (pi fold, followup.2)
author ─► submit; grade climbs ladder on derivation + artifact
```

## Diagram

```text
toy demo ─► pi child (pi -p) ─► flappy demo
                 │ pi tape (WAL)
                 ▼
             supervisor fold ─► finished
```

## Pseudocode

```python
run_pi_demo(prompt)          # one experiment Run, env-set run-id
assert supervisor_derives(run_id) == "finished"
assert artifact_ok("flappy.html")
```

| Field | Value |
|---|---|
| Intent | pi engine proven live under supervision, demo-scale |
| Lane | standard |
| Output | flappy demo artifact built by pi; pi Run derivation |
| Depends on | followup.2 (pi finish derivation), followup.4 (bind resolution) |

## Acceptance

| Case | Expected |
|---|---|
| pi demo run | one pi child builds `flappy.html` in the run folder; supervisor derives that pi Run `finished` from its tape |
| demo artifact | `flappy.html` present in the pi Run's folder and passes `node --check` on its extracted module |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment for both the submit Run and the pi child Run, and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** a pi Run does real demo work under
  the supervisor, and the supervisor — not the child —
  proves it finished.
- **Prove by:** the pi Run's derivation row
  (`finished`), the artifact, and the stamped ledger
  lines.
- **Done when:** pi-built flappy demo is in the run
  folder and its Run derives `finished`, observed.

## Tests

Demo drive, observed: spawn the pi child with
`BP3_RUN_ID` exported in its environment; after it
exits, `bp3 harness supervisor` (or the per-Run
derivation file) shows `finished` for that run-id.
Artifact smoke: `node --check` passes on the module
extracted from `flappy.html`. No seeded-hung or
watchdog case in this exp — that is dogfood.2 design
territory.

## Context

Same toy as dogfood.1 on purpose: one variable changes
(the engine), so the comparison means something. The
full pi toy-quest drive and the pi supervisor rethink
live in dogfood.2; this exp only proves a supervised
pi demo Run end to end.
