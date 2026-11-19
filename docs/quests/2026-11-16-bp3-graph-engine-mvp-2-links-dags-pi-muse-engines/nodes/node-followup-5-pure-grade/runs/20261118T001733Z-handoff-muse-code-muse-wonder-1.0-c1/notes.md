# followup.5 pure-grade — author run notes

Run: 20261118T001733Z-handoff-muse-code-muse-wonder-1.0-c1

## What changed
- Pure grade: audit/grade/verify children in bp3g-grade and
  the grade/verify workers in bp3g-node return verdicts as
  data and make zero `bp3 g u` calls; only the looper casts.
- One combined cast: `grade --verdict ... --verify-verdict
  pass|fail [--mechanical]` is one ledger line that sets
  both grade_ok and verify_ok (engine: main.ml + store.ml
  fold). No verdict race remains in the fixtures.
- Pushbacks before any cast, named: superseded - re-grade,
  empty fix, owner gate (blocked read / owner-only fix).
- Fix ledger: looper opens OPEN (fix verbatim + commit);
  author records RESOLVED in its fix commit (bp3g-node
  author brief); grader never edits the record.
- Mechanical never blocks: `--mechanical` needs_fix always
  returns todo at any cycle; cap counts disagreement only
  (same row failing after its fix = disagreement, no flag).
- Audit reuse (warden #9): validations transport returns
  prior_evidence from the validations log + author notes;
  audit reuses typed pass rows with reused_from source and
  re-runs only rows lacking evidence.

## Verification (observed)
- node test/bp3g-grade.test.mjs: ok (pure children, one
  cast, replay, 3 pushbacks, ledger OPEN, mechanical at
  cap, disagreement at cap, audit reuse).
- node test/bp3g-node.test.mjs: ok (looper casts once,
  fix rides verbatim, RESOLVED brief).
- node test/node-loop, bp3g-land, bp3g-conduct: ok.
- ./test/g.sh: ok (combined cast one ledger line;
  mechanical todo at cap with empty inbox; disagreement
  blocks at cap; --verify-verdict misuse E_USAGE).
- make check: exit 0, full gate green (all suites).

## Lessons
- A combined cast needs engine support; counting casts in
  workflow fixtures alone would have left ship+pass as two
  ledger lines and kept the race window.
- Test mocks that dispatch on `Run exactly` swallow a new
  looper apply step as a read; dispatch on the label first.
- Empty-fix escalation only bites when the verdict names
  no fix and no failed row; failed rows name their fix.
