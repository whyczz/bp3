# grade notes — exp-followup-2-workflow-birth c1

Verdict: fix_first -> needs_fix (code correct; one gated acceptance unproven).

- Rung 1-2: node handed_off at 6f124a6; diff implements all four birth defects (deskNote reads, verbatim context, claim-session find-tape, E_RENDER_STALE check over all four workflows). Comments agree with code; renders are regenerated copies.
- Rung 3 (run, not read): bp3g-grade/land/node, node-loop, bp3g-conduct tests ok; skills.sh ok (134 assertions); harness.sh passed; live stale-render probe refused E_RENDER_STALE naming render+source, restored fresh ok.
- Blocking gap: "full conduct (node -> grade -> land) from a foreign-dialect conductor root, zero read refusals" has only mock-host fixtures (bp3g-conduct.test.mjs: host mocked). No real conduct run observed, so the gated row stays missing.
- Lesson: mock conduction proves wiring, not birth. The next cycle needs one real foreign-root conduct with the tape as evidence; until then this node cannot ship.

Grade call outcome: E_ILLEGAL_EDGE — node already blocked at 2026-11-17T10:19:55Z by sibling verify for the same gated gap ("no real full conduct"). Grade intent needs_fix could not be recorded; state left untouched.
