# grade notes — exp-mvp-3-ready-set-timing c1

- Code review (code-reviewer): diff at b765d07 read in full; deps/cycle in main.ml+store.ml, waves/starved/timing derived on read, setup in render.ml, induct-node loop. Comments agree with code; generated induct-node copies identical; no critical/major defect found.
- Rung 3 observed: ./test/ready.sh -> "ready tests: ok"; node --test test/induct-node.test.mjs -> "induct-node tests: ok"; make check exit 0.
- Verdict is needs_fix, not ship: the gated evidence matrix row "adherence: no hand-edited state" (rung 2) is verdict missing with no typed evidence. Per grade rules any gated fail/missing row blocks ship, even when code/tests pass.
- Lesson: a clean tree and identical generated copies observed locally do not substitute for the typed evidence row the matrix requires; supply that row before re-grade.
- Grade call attempted needs_fix but refused E_ILLEGAL_EDGE: exp already blocked (inbox: fresh ready/induct/make-check pass but gated matrix row adherence:no-hand-edited-state missing, since 2026-11-17T03:17:03Z). Legal edges now resume/delete only; grade cannot be cast from blocked without human resume. Intended verdict remains needs_fix for the same missing gated row.
