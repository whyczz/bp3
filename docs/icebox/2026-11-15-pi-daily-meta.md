---
status: frozen
date: 2026-11-15
promoted: null
---

# Pi daily meta (the speed setup, measured — second quest)

## Context

Frozen 2026-11-15 at the framing of the pi-engine-conductor
quest. The owner split the ask in two: first `/induct`
working on pi (the engine executor), then this — how pi
itself is used well day to day. This entry carries the
second half so the first quest stays lean.

## Sketch

- The meta, measured not folkloric: context and cache
  discipline (what stays in the conductor session, when
  /compact helps or hurts), tool-surface discipline
  (closed toolbox mid-job, `--tools` per role), model
  routing per job kind with cost numbers, session reuse
  (`-c`, `--fork`) vs cold starts.
- Code search/write on pi: bare pi ships grep-by-bash;
  candidates to evaluate on evidence — ast-grep style
  structural search, LSP-backed tools (omp's pitch),
  hash-anchored editing. Each candidate gets a timed
  task battery, not a vibe.
- Extension hygiene: what earns a place in
  `~/.pi/agent/extensions/`, pinned and reviewed; the
  wider extension meta (pi.dev packages) re-surveyed at
  thaw — stars/downloads from the 2026-11 dossier
  (`docs/dossiers/bp3-pi-basics.md`) are stale by then.
- Output shape: a short pinned setup (extensions, roles,
  models, AGENTS.md guidance) with the numbers that
  justify each line; folklore either confirmed or buried.

## Blockers

- Depends on the pi engine quest landing first: role
  files, dispatcher, and registry measurements built
  there are this quest's instruments.
- Vendor claims circulate unverified (cache savings,
  subagent speedups); the thaw starts by designing the
  measurements, not collecting more claims.

## Promotion trigger

Thaw when the pi-engine-conductor quest lands
(`goal_fin` on master) and the human wants the daily
setup measured — or when a pi drive's scorecard shows a
cost surprise worth chasing.
