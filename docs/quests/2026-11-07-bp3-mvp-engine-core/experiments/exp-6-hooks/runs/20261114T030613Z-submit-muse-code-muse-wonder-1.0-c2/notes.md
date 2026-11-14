# exp-6-hooks submit run (cycle 2) — lessons

- Fixed the cycle-1 review blocker: the `SessionStart` sweep
  in `src/quest/hooks.ml` now gates on `last_seen_epoch` —
  bindings record a float epoch beside `last_seen_ts`, every
  witnessed event touches it, and only bindings untouched for
  `stale_after_s` (900s) are swept as `run_unsettled`. A fresh
  parallel Run is no longer marked unsettled by a neighbour's
  session start. Legacy registry entries without the epoch
  fall back to `started_epoch`.
- Fixtures in `test/hooks.sh`: the killed-session case now
  backdates its binding (`age_binding` rewrites the registry
  in the git dir) before sweeping; a new live-parallel case
  asserts a fresh `SessionStart` sweeps nothing, then ageing
  one of two bindings sweeps only that one.
- Live evidence, for real this time: a headless `claude`
  session in a scratch repo ran one env-preset command. Hooks
  in `.claude/hooks.json` alone never fired (no registry, no
  ledger lines); the same hooks in `.claude/settings.json`
  produced `run_started` (real session id), `usage_recorded`,
  `run_settled`. So `bp3 skills install` now also merges the
  hooks into `.claude/settings.json`, preserving other keys
  (asserted in `test/skills.sh`, 46 assertions), and this
  repo's own `.claude/settings.json` is installed.
- Observed limit: the live `usage_recorded` summed zero
  tokens — this host's `PostLLMCall` usage did not reach the
  tally. Fixture payloads with real usage fields sum
  correctly; the live token path wants a second look.
- Wrote the missing `experiments/exp-6-hooks/EXPERIMENT.md`:
  acceptance table, cycle evidence, and the still-open
  registry `.tmp` locking minor from cycle-1 review.
- Verify: `make check` green (lint, skills 46, q, tape,
  hooks, induct-exp). This session itself runs on Muse,
  which does not load `.claude` hooks, so no event lines were
  expected — or seen — for this Run in the real ledger.
