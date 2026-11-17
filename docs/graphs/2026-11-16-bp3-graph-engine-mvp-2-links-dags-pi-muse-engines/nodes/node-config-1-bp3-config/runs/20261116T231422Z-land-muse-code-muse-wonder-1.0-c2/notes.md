# Land notes — exp-config-1-bp3-config c2

- State on entry: `approved` at cycle 2, commit `3c47fe532642369348656be958eb577fc662881d`, legal edges include `land`.
- Deliverable: bp3 config store and view door (`src/quest/config.ml`, `src/quest/main.ml`) with `test/config.sh` covering mkdir-failure attribution and scoped thresholds claim.
- Fix commit `3c47fe5` attributes mkdir failures and scopes the thresholds claim; prior feat `229a6ba` added the config store/view door.
- Working tree clean at land time; no uncommitted changes carried into the landing.
- Landing via `bp3 q ... u exp-config-1-bp3-config land` directly from this child as instructed.
