# rename.1 grade run — notes

Run: 20261117T094456Z-grade-muse-code-muse-wonder-1.0-c1 (claimed via one-time link; run_id matched the brief).
Reviewer: code-reviewer procedure (correctness, design, tests, comments-as-claims). Verdict: ship.

## Evidence (rungs 1-4; no whole-tape read needed)

- Rung 1: EXPERIMENT.md acceptance — 7 gated cases, no open design questions, no deferred rows blocking.
- Rung 2: git status clean; HEAD = bound commit 4e0f1bd; no ledger paths in diff (history frozen). Fold lives only in src/graph/store.ml (fold_edge/fold_state_name/fold_type_key) with an accurate compat comment. Live read returns handed_off, commit 4e0f1bd, legal grade/verify. Naming skill teaches graph/node + bp3g.
- Rung 3 (run, not read): sh test/g.sh -> g tests: ok; sh test/bp3g.sh -> bp3g-conduct tests: ok; sh test/skills.sh -> skills tests: ok (128 assertions); ./bin/bp3 q foo -> exit 2.
- Rung 4: no severity findings; no alias door, renders regenerated, tests pin new verbs and can fail.

## Lessons

- The one naming-skill hit for the old door spelling is documentation of its refusal, not a live synonym; vocabulary-zero greps need that distinction.
- g.sh is the slow gate; run it early so its result lands before the verdict call.

Grade edge landed: ledger grade ship line stamped run_id=20261117T094456Z-grade-muse-code-muse-wonder-1.0-c1 at 2026-11-17T09:50:05Z, commit 4e0f1bd. State remains handed_off until verify (plan requires grade+verify) — expected.
