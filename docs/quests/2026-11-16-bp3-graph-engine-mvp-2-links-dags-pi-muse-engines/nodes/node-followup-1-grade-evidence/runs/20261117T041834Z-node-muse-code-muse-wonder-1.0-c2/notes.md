# Audit notes — exp-followup-1-grade-evidence @ 8411e0a

Lessons: cycle-2 fix is narrow and trustworthy — canonical one-liner transport plus tolerant `lineHasFile`/`folderLines` parsing passes canonical, prose, and newline-string variants while missing-file folders still fail. Evidence contract holds end-to-end: validations mint adherence rows before the audit, untyped rows re-collect once then explicit `audit_failure` with no verdict cast and no cycle burn, empty stdout quoted as machine token, race named. Both renders synced (diff empty); `git status --porcelain` clean.

Matrix (verbatim JSON):

```json
[
  {"case": "untyped row produced", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "evidence still uncollectable", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "real defect still gates", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "regression: config.1 shape", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "cycle accounting", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "validations mint adherence rows", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "regression: mvp.3 empty-stdout trap", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"},
  {"case": "verdict race named", "rung": 3, "evidence": {"kind": "command", "ref": "node test/induct-grade.test.mjs", "quote": "induct-grade tests: ok"}, "verdict": "pass"}
]
```
