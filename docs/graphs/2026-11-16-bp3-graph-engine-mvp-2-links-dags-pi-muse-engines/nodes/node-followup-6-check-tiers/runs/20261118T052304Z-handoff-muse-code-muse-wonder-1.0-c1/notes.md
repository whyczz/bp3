# followup.6 check-tiers — author run notes (cycle 1)

## What shipped

- `make check-fast` (fast tier) and `make check-changed`
  (change-scoped selector), both doorways into
  `scripts/check-changed.sh`, which carries the single
  path->suite table and the fast-tier membership table.
- `scripts/check-retired-terms.sh`: retired-term sweep
  (`GOAL.md`, `QUEST.md`, `EXPERIMENT.md`) over live
  surfaces including `skills/**` and the rendered copies;
  runs before any suite in both tiers. Per-path fossil
  exemptions with reasons (migration rename table, the
  sweep's own declaration); `docs/` record space and
  `test/` fixture data are out of scope by definition.
- `test/check-tiers.sh` fixtures (14 assertions): the
  four selector mappings, unknown-path fail-safe,
  fast-tier membership, planted-term timing/file:line,
  fossil pass. They run as the `check-tiers` fast suite.
- Cycle discipline text in `skills/bp3g/SKILL.md`
  (re-rendered): per cycle `check-changed`/`check-fast`;
  full `make check` only when acceptance names it or the
  conductor asks at handoff; grade/land unchanged.
- The sweep immediately caught real stale terms:
  `EXPERIMENT.md` in `skills/bp3g-landing-demo` and
  `skills/bp3g-no-human` (plus renders). Fixed to
  `NODE.md` at the source and re-rendered — exactly the
  followup.3 failure mode, now costing seconds.

## Measured (this machine, load avg ~5)

- Retired-term sweep alone: 0.076 s.
- `make check-fast`: exit 0, wall 54 s (target < 120 s).
  Suites: lint, check-skills, skills, build, pi-tree,
  bp3-pi, bp3g, check-tiers. `test/harness.sh` (the
  wall-clock sleep/watch suite) is full-tier only.
- `make check-changed` on this run's own diff: exit 0,
  wall 54 s, 9 suites (fast tier + test/check-tiers.sh).
- Full `make check`: exit 0, wall 390 s, all suites ok.
  The `check` recipe is byte-identical to HEAD; no
  existing test was edited, skipped, or re-timed.

## Lessons

- `test/g.sh` alone is ~126 s, so it cannot sit in a
  <120 s fast tier; it belongs to the `src/**` mapping,
  paid only when `src/` changes. Tier membership must
  be set from measured suite times, not suite names.
- A sweep that includes renders earns its keep: stale
  generated copies fail even when sources are fixed,
  which forces the re-render in the same cycle.
