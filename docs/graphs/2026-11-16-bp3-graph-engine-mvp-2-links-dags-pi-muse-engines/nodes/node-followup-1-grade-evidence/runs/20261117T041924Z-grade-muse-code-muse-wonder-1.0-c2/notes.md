# Grade notes — exp-followup-1-grade-evidence cycle 2

Verdict: ship (code-reviewer: ship).

- Rung 1: EXPERIMENT.md cycle-2 fix is verbatim and closed; no open design question.
- Rung 2: HEAD == bound commit 8411e0a; `git status --porcelain` empty; both renders byte-identical.
- Rung 3: `node test/induct-grade.test.mjs` -> "induct-grade tests: ok" (run, not read). Covers canonical/prose/string/empty/missing-file run-folder variants; missing file still gates `needs_fix`.
- Review: `folderLines`/`lineHasFile` veto affirmed absence before affirming presence; canonical `=yes/=no` handled exactly. Minor: fallback bare-mention is looser than the "only affirmed presence" comment, but no gated case falsifies it.
- Lesson: grade evidence must be collected by running the canonical one-liner and the test suite, not by trusting the supplied matrix.
