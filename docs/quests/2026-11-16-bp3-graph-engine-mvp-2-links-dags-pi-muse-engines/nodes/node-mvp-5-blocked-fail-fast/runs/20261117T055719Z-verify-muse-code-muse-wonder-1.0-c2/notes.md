# Verify notes — exp-mvp-5-blocked-fail-fast c2

Claims checked fresh (verify stance, not claimed green):
- node test/induct-node.test.mjs — induct-node tests: ok (exit 0)
- node test/pi-tree.test.mjs — pi-tree tests: ok (exit 0)
- ./test/blocked.sh — blocked tests: ok (exit 0)
- git status --porcelain — empty, exit 0; HEAD == bound commit f5b434d

Lessons:
- The three test commands exactly cover all gated matrix rows; no rung-5 tape read was needed.
- Run folders are git-ignored, so creating the verify run folder does not dirty the tree.
- Pi-tree proof uses real OS processes (kill(pid,0) death), stronger than state-only inference.
