# followup.6 check-tiers — audit notes (grade child)

Run: 20261118T054337Z-node-muse-code-muse-wonder-1.0-c1
Commit: 0f60c7a50a826ca932a99c0097a2baf7ac227877 (work f96a969)

## Lessons

- Every acceptance case was decided at rung 2 (committed code/diff) or
  rung 3 (tests I ran myself); zero whole-tape reads were needed.
- Measured by me on this machine: retired-term sweep 0.079s,
  `make check-fast` 55.251s exit 0 (8 suites, no harness.sh),
  `test/check-tiers.sh` 0.629s (14 assertions), full `make check`
  6m45.384s exit 0 — corroborates the handoff's 54s/390s claims.
- Independent planted-term probe (QUEST.md in skills/demo/SKILL.md)
  failed the sweep in 0.084s naming file:line, before any suite ran.
- The `check` recipe is byte-identical before/after f96a969 (diff is
  only .PHONY plus the two new targets); no file was deleted.

## Evidence matrix

```json
[
  {"case": "fast tier exists", "rung": 3, "evidence": {"kind": "command", "ref": "time make check-fast", "quote": "check-changed: suites: lint check-skills skills build pi-tree bp3-pi bp3g check-tiers"}, "verdict": "pass"},
  {"case": "full tier unchanged", "rung": 2, "evidence": {"kind": "command", "ref": "diff /tmp/make-before.txt /tmp/make-after.txt (git show f96a969^:Makefile vs HEAD:Makefile)", "quote": "44a45,53"}, "verdict": "pass"},
  {"case": "selector maps skills", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-changed.sh --list skills/bp3g/SKILL.md", "quote": "check-skills\nskills\nbp3g"}, "verdict": "pass"},
  {"case": "selector maps src", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-changed.sh --list src/graph/main.ml", "quote": "build\ng"}, "verdict": "pass"},
  {"case": "selector maps renders", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-changed.sh --list .agents/workflows/bp3g-grade.js", "quote": "skills-check\nwf:bp3g-grade"}, "verdict": "pass"},
  {"case": "unknown path fails safe", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-changed.sh --list (no changed paths)", "quote": "check-changed: no changed paths; fast tier (fail-safe)"}, "verdict": "pass"},
  {"case": "cycle discipline text", "rung": 2, "evidence": {"kind": "file", "ref": "skills/bp3g/SKILL.md:206", "quote": "   asks; grade and land gates keep the full `make check`,"}, "verdict": "pass"},
  {"case": "no suite weakened", "rung": 2, "evidence": {"kind": "command", "ref": "git diff --diff-filter=D --name-only f96a969^ HEAD", "quote": "(empty stdout, exit 0)"}, "verdict": "pass"},
  {"case": "regression", "rung": 3, "evidence": {"kind": "command", "ref": "time make check", "quote": "full-exit:0"}, "verdict": "pass"},
  {"case": "retired-term sweep", "rung": 3, "evidence": {"kind": "command", "ref": "time ./scripts/check-retired-terms.sh", "quote": "retired-term sweep: ok"}, "verdict": "pass"},
  {"case": "planted stale term", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-retired-terms.sh --root $W (planted QUEST.md probe)", "quote": "skills/demo/SKILL.md:5:See QUEST.md here."}, "verdict": "pass"},
  {"case": "fossil stays legal", "rung": 3, "evidence": {"kind": "command", "ref": "./test/check-tiers.sh", "quote": "check-tiers tests: ok (14 assertions)"}, "verdict": "pass"}
]
```
