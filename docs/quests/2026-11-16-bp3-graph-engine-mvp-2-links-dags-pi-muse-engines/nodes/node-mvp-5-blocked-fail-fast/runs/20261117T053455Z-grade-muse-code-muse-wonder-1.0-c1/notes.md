# Grade notes — exp-mvp-5-blocked-fail-fast cycle 1

Verdict: fix_first -> needs_fix

## Claims checked
- Typed failure blocks once verbatim and exits; orphan replaced not blocked; bubble facts only; needs_fix rides verbatim / cap blocks; node read carries blocked reason/checkpoint/since; stale refusal, resume fresh, siblings ready.

## Findings
1. [critical] Pi acceptance unproven — EXPERIMENT.md Pi cases (tree bubbles, whole tree dies, fresh revival, unreaped grandchild, root dies) require real Pi process-tree/process-table proof. Commit 4d00100 has no Pi spawn/process code or test; handoff notes.md admits Pi proof stays with Pi drive and only Muse bubble lands. No named successor exp owns them, so missing not deferred. Evidence matrix rows for those five cases are missing at rung 3.
   Fix shape: land Pi drive proof with process-table evidence, or amend EXPERIMENT.md to defer those cases to a named exp.

## What passed
- Rung 3 run by grader: `node test/induct-node.test.mjs` -> induct-node tests: ok; `./test/blocked.sh` -> blocked tests: ok. Copies .agents vs skills identical; node --check ok.
- Code walk: classify/ blockAndExit/ bubble in induct-node.js agree with comments; mock tests assert one block/no retry/one replacement and can fail; blocked.sh covers cap/stale/resume/checkpoint/siblings.

Unchecked: whole-tape rung 5 not needed; verdict decided at rungs 1-3.

Lesson: a Muse-form bubble does not satisfy a Pi process-death acceptance; deferral must name its owning exp.

## Grade edge attempt
Grade call with BP3_RUN_ID=20261117T053455Z-grade-muse-code-muse-wonder-1.0-c1 returned E_ILLEGAL_EDGE (state blocked, legal resume/delete). Node was already blocked at 2026-11-17T05:35:56Z with Pi-missing reason by concurrent drive; intended needs_fix verdict is therefore recorded as blocked, not cast. Verdict returned to parent is the printed refusal JSON verbatim.
