# exp-7-landing-vocabulary — author notes

- Report words, not states: `exp_fin`/`quest_fin` added as a `fin`
  field beside `state`/`rollup` (`landed` unchanged in data); no new edges.
- Surfaces synced: `src/quest/render.ml` + `main.ml` land verdicts,
  `skills/induct/SKILL.md`, `induct-exp.js` outcome (`exp_fin`),
  QUEST.md terms, tests (`test/q.sh`, `test/induct-exp.test.mjs`),
  installed copies via `bp3 skills install --harness=muse`.
- `quest_fin` in `bp3 q r` fires when rollup is `landed` (its gate);
  the word names promotion to master in conductor/landing reports.
- Lesson: `bp3 skills install` also installs the workflow copy;
  staged exp-6 ledger deletions seen at start were restored untouched.
- Verified: `make check` green (skills, q, worktree, tape, hooks, induct).
