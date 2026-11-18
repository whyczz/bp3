# Audit notes — exp-followup-1-grade-evidence @ 5cce4cc

Lessons: grade decided at rungs 1–3 (records, bound-commit diff/code,
tests run); zero whole-tape reads. The deterministic validations
plugs, one audit-internal re-collect, explicit `audit_failure`, and
the named expected verdict race are all exercised by the committed
mock-host tests, which pass. Live corroboration: exp state
`handed_off`, bound commit matches, `git status --porcelain`
stdout empty exit 0. No per-Run derivation log exists yet for this
audit run, so no rung-5a pointer was needed.

```json
[
  {"case": "untyped row produced", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — untyped/recollect blocks test/induct-grade.test.mjs:180-193,443-459", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "evidence still uncollectable", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — audit_failure blocks test/induct-grade.test.mjs:182-193,461-477", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "real defect still gates", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — fail/dirty blocks test/induct-grade.test.mjs:195-205,490-497", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "regression: config.1 shape", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — config.1 replay test/induct-grade.test.mjs:443-459", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "cycle accounting", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — retry mints no new link test/induct-grade.test.mjs:443-459", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "validations mint adherence rows", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — validations precede audit test/induct-grade.test.mjs:123-168", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "regression: mvp.3 empty-stdout trap", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — empty-stdout token test/induct-grade.test.mjs:479-488", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "verdict race named", "rung": "3", "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs — verdict race test/induct-grade.test.mjs:499-511", "quote": "induct-grade tests: ok"}, "verdict": "pass"}
]
```
