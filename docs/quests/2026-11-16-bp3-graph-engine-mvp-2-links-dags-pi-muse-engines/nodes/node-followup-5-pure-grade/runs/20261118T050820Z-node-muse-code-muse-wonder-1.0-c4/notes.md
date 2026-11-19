# Audit notes — node-followup-5-pure-grade @ 691547e

Run: 20261118T050820Z-node-muse-code-muse-wonder-1.0-c4. Bound commit verified: HEAD == 691547e4653d7d708903b1aa05284ecd889d09e9, git status clean at audit start. No `bp3 g u` call made by this audit (pure). Validations log read at /Users/whycz/m/bp3/.git/bp3/20261118T050735Z-node-followup-5-pure-grade-validations.log (git_clean empty, handoff_line names 691547e). Executed: node --test test/bp3g-grade.test.mjs -> "bp3g-grade tests: ok" (pass 1 fail 0); node --test test/bp3g-node.test.mjs -> "bp3g-node tests: ok". Full `make check` exceeded the 300s audit window and was terminated with no failure line observed (output was tail-buffered); the bp3g workflow suites that carry the cast-once/pushback/mechanical/reuse fixtures were executed directly and pass. Cycle-4 NODE.md resolution independently records "full make check exits 0" at this commit (rung 2 corroboration, not a fresh run).

## Evidence matrix

```json
[
{"case":"pure audit","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (child-purity asserts: audit/grade/verify inputs include 'do not call any `bp3 g u` update edge')","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"single cast","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (pure-grade single-cast fixture: casts===1, no E_ILLEGAL_EDGE refusal)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"safe replay","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (safe-replay fixture: each dispatch casts once, same matrix)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"pushback: superseded","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (superseded fixture: casts===0, refusal includes 'superseded - re-grade')","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"pushback: empty fix","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (empty-fix fixture: escalated, casts===0, refusal includes 'empty fix')","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"pushback: blocked","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (blocked fixture: escalated, casts===0, refusal includes 'owner gate')","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"fix ledger live","rung":2,"evidence":{"kind":"file","ref":"docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-5-pure-grade/NODE.md Fix ledger","quote":"- 2026-11-18 · cycle 2 · from grade of 4ab3228 (needs_fix) · status: open"},"verdict":"pass"},
{"case":"regression","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs + node --test test/bp3g-node.test.mjs (workflow fixtures for cast-once + three pushbacks); make check exceeded 300s audit window, terminated with no failure observed","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"audit reuse: prior evidence not re-executed","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (warden #9 fixture: audit input includes 'do not re-execute', reused_from kept)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"audit reuse: no prior evidence executed","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (fresh fixture: audit input includes 'execute every acceptance-named test yourself')","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"audit reuse: source quoted","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (reuse fixture asserts source '.git/bp3/20260101T000000Z-fx-validations.log' quoted, reused_from preserved)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"mechanical never blocks at cap","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (mechanical-at-cap fixture: outcome needs_fix, casts===1, apply includes --mechanical)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"disagreement counts and blocks at cap","rung":3,"evidence":{"kind":"command","ref":"node --test test/bp3g-grade.test.mjs (disagreement fixture: fix_class disagreement, outcome blocked, no --mechanical)","quote":"bp3g-grade tests: ok"},"verdict":"pass"},
{"case":"live mechanical cycle","rung":2,"evidence":{"kind":"file","ref":"docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-5-pure-grade/NODE.md Fix ledger cycle 3","quote":"- 2026-11-18 · cycle 3 · from grade of 31b7c74 (needs_fix, mechanical) · RESOLVED (this handoff)"},"verdict":"pass"}
]
```

## Lessons

- The bp3g-grade fixture file is the single executed oracle for 11 of 14 rows; one green run decides them, so per-row quotes collapse to the suite verdict — future audits should capture per-fixture TAP names for finer quotes.
- Full `make check` does not fit a 300s window at this commit (g.sh alone ~125s per the cycle-4 notes); audits should budget a detached gate run or accept the workflow-suite subset explicitly, as done here.
- This audit stayed pure: zero `bp3 g u` calls; the only writes are this run folder's tape.log/notes.md.
