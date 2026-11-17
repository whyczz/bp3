# mig.2 traverse-rename — run notes

- Rename is a bijection, executed with `git mv`: `skills/induct` -> `skills/traverse`,
  `skills/induct-quest` deleted (merged into `/traverse`), `skills/induct-quest-no-human`
  -> `skills/traverse-no-human`, `workflows/induct-exp.js` -> `workflows/node-loop.js`.
  `induct-grade`/`quest-land` workflow names stay; they move under `skills/traverse/`.
- Installer (`bin/bp3`) now copies `node-loop induct-grade quest-land` from
  `skills/traverse/workflows/`; renders regenerated with `bp3 skills install --harness=all`,
  never hand-edited. Old render dirs and `.agents/workflows/induct-exp.js` removed first —
  the installer only adds, so stale renders must be deleted by hand.
- `.pi/settings.json` keeps stale exclusions after install; pruned the three `induct*`
  entries with `jq` so old names resolve nowhere.
- Tests renamed with the surface: `test/induct-exp.test.mjs` -> `test/node-loop.test.mjs`,
  `test/induct.sh` -> `test/traverse.sh`; `test/skills.sh` now asserts traverse renders and
  that `induct`/`induct-quest`/`induct-exp` are absent in every harness.
- Verified: `./test/traverse.sh` (node-loop parity on the old induct-exp fixtures),
  `./test/skills.sh` (121 assertions), full `make check` exit 0.
