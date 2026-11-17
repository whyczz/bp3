# Verify notes — exp-followup-1-grade-evidence @ 5cce4cc

Run: 20261117T035551Z-verify-muse-code-muse-wonder-1.0-c1 (verify, cycle 1)

## Fresh evidence (rungs 1-3)
- Rung 1: EXPERIMENT.md acceptance = 8 cases (untyped re-collect, audit_failure, real defect gates, config.1 replay, cycle accounting, validations mint adherence, mvp.3 empty-stdout, verdict race named).
- Rung 2: HEAD == bound commit 5cce4cc8c272a32c9a7e850cb9acea79411a026b; git status --porcelain empty (exit 0); handoff run folder 20261117T033939Z-handoff-... present on fresh ls with tape.log+notes.md; exp state handed_off cycle 1 via bp3 read.
- Rung 3: node test/induct-grade.test.mjs -> "induct-grade tests: ok" (exit 0). make check run in tape (see tape.log for full gate result).

## Verdict basis
- Evidence matrix gated row "adherence: run folder present" is fail ("no run folder with tape.log and notes.md"), minted by the deterministic validations pipeline at grade time. Per brief: any gated fail means work is not correct. Grade sibling already cast needs_fix on same row and noted fresh ls discrepancy is for author cycle (transport observation vs pipeline expectation), not to override.
- Therefore verify casts fail despite fixture tests green, matching dirty-tree gating parity. Do not ship over a gated adherence fail.

## Lessons
- A validations plug is only as trustworthy as its transport observation; a live minted fail gates even when a later direct ls disagrees.
- Verify must re-run tests fresh (done) but must not override a gated matrix fail with fresh-green fixtures.

## Verify cast
- Cast verify --verdict fail; refused E_ILLEGAL_EDGE (state blocked, legal resume/delete) after grade sibling moved state first — expected verdict race, named. Fresh induct-grade tests ok; gated run-folder-present fail determines fail verdict regardless of make check partial run in tape.
- Fresh make check: MAKE_CHECK_EXIT:0 (full gate pass, incl. induct-grade/traverse/skills/q/harness). Gated adherence fail still determines fail verdict per brief.
