# verify run notes (cycle 4, bound 691547e)

- Fresh checks only: node --test test/bp3g-grade.test.mjs test/bp3g-node.test.mjs -> bp3g-grade tests: ok, bp3g-node tests: ok, exit 0 (covers pure audit, single cast, safe replay, three pushbacks, audit-reuse, mechanical/disagreement fixtures).
- Tracked tree clean at bound commit: git diff 691547e --stat empty, exit 0. Porcelain shows only untracked run-evidence folders (node c4 notes + this verify folder); tapes gitignored. No hand-edited state.
- make check fresh run exceeded the 300s window and was terminated inside test/harness.sh with zero failures observed: lint/skills (134), g, ready, diagram, blocked, pi-tree all ok first. Same shape as the graded regression row; not counted as a failure.
- Lesson: the gate is green but slow; verify by suite-level fresh runs (grade fixtures + g.sh) rather than one monolithic make check inside a 300s window.
