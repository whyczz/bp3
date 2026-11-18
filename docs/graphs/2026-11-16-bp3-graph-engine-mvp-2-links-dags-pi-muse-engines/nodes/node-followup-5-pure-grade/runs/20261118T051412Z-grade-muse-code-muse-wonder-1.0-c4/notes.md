# Grade run notes (cycle 4, commit 691547e)

- Verdict: ship (code-reviewer ship). Pure grade: no edits, no `bp3 g u` cast.
- Rungs 1-2: NODE.md acceptance + fix ledger (cycle 4 RESOLVED) match the bound commit; diff is caching/batch ledger reads (gitx/store/main) plus harness-narrowed tape scan, with invalidation on every update-ref path (commit_files incl. create_branch_commit delegate, both land sites in main.ml).
- Rung 3 (run, not read): `node --test test/bp3g-grade.test.mjs` ok; `node --test test/bp3g-node.test.mjs` ok. Full `make check` not re-run (author-verified exit 0 at this commit; exceeds the grade window).
- Lesson: cache correctness rests on enumerating every ref-move site; grep for update-ref is the cheap audit. Batch fallback fails closed to per-read git calls.
- Pre-existing untracked sibling node run folder (20261118T050820Z-node-...) was present before this run and is not part of the bound commit.
