# followup.3 cycle 3 — grade-path hygiene

Claimed run 20261117T212415Z-handoff-muse-code-muse-wonder-1.0-c2.

Fixes:
- `.gitignore` now ignores `.bp3-context.json` and `**/runs/*/tape.log` (runtime residue); `notes.md` stays deliberate. Verified live: this run's tape and the desk context no longer appear in `git status --porcelain`.
- Grade probe in `skills/bp3g/workflows/bp3g-grade.js` resolves the handoff ledger via `bp3/node/<graph>/<node>` (post-migration scheme, `Store.node_branch`); retired `bp3/exp/` hardcode removed (2 sites). Stale `EXPERIMENT.md` prompt refs updated to `NODE.md`. Render regenerated (`bp3 skills install`), `skills check` fresh.

Regression tests kept in `test/`:
- `test/bp3g-grade.test.mjs`: asserts the validations probe uses `bp3/node/...` and carries no `bp3/exp/`.
- `test/cleanliness.sh` (wired into `make check` + shellcheck lint): residue present across a step keeps `git status --porcelain` empty; `notes.md` is not ignored and stays visible.

Lessons:
- A tracked `tape.log` still dirties when appended; ignoring only helps once new runs leave tape untracked — restore, never commit, the residue append.
- Untracked-directory porcelain hides ignored files; use `--untracked-files=all` when asserting authored evidence is visible.
