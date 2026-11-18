# exp-mvp-1-link-claim — audit notes (run 20261117T003239Z-node-muse-code-muse-wonder-1.0-c1)

## Lessons

- The build Run predates the mechanism it built: its derivation log opens with a legacy `init_record`, not a link claim, and no handoff run config sits in the claim store. Bootstrap Runs cannot claim links that do not exist yet; the shipped mechanism is proven by `test/link.sh` and the Pi suite instead.
- Prompt/brief assembly order matters (build Run lesson, confirmed in code): workflows mint links before building child briefs, or claim instructions arrive empty.
- Worktree dirt needs a timestamp check before it counts against a Run: the `.agents/workflows/*` modifications are byte-identical copies of the committed `skills/traverse/workflows/*`, stamped at this audit session's start (skill install), not build-Run residue.

## Evidence matrix

```json
[
{"case":"mint + claim","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"one winner","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"by-session join","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"session-id offered vs not","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"Pi engine MVP v2 nesting","rung":3,"evidence":{"kind":"command","ref":"node --test extensions/bp3-pi/test/bp3-pi.test.mjs","quote":"pass 13"},"verdict":"pass"},
{"case":"missing Pi extension in child","rung":3,"evidence":{"kind":"command","ref":"node --test extensions/bp3-pi/test/bp3-pi.test.mjs","quote":"missing bp3-pi extension refuses E_SETUP before any spawn"},"verdict":"pass"},
{"case":"run config replaces InitRecord","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"claim CAS is real (red-chair)","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"depth cap (red-chair)","rung":2,"evidence":{"kind":"grep","ref":"src/quest/harness.ml:2219","quote":"if depth > thresholds.Config.depth_cap then"},"verdict":"pass"},
{"case":"stale mint cleanup","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"quoting safety","rung":3,"evidence":{"kind":"command","ref":"./test/link.sh","quote":"link tests: ok"},"verdict":"pass"},
{"case":"env-set run-id","rung":1,"evidence":{"kind":"ledger","ref":"exp-mvp-1-link-claim ledger handoff line","quote":"{\"ts\":\"2026-11-16T23:48:00Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"09b9d8d01646ca0f2faeb273bbf227aaa9c43fb3\",\"verdict\":null,\"reason\":\"link mint/claim CAS, run config replaces InitRecord, make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261116T231553Z-handoff-muse-code-muse-wonder-1.0-c1\"}"},"verdict":"pass"},
{"case":"adherence: handoff edge called by the child directly","rung":2,"evidence":{"kind":"file","ref":"skills/traverse/workflows/node-loop.js","quote":"moves through `bp3 q u`, called directly by the author child;"},"verdict":"pass"},
{"case":"adherence: env-set run-id stamped by bp3","rung":1,"evidence":{"kind":"ledger","ref":"exp-mvp-1-link-claim ledger handoff line","quote":"{\"ts\":\"2026-11-16T23:48:00Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"09b9d8d01646ca0f2faeb273bbf227aaa9c43fb3\",\"verdict\":null,\"reason\":\"link mint/claim CAS, run config replaces InitRecord, make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261116T231553Z-handoff-muse-code-muse-wonder-1.0-c1\"}"},"verdict":"pass"},
{"case":"adherence: clean commit","rung":2,"evidence":{"kind":"command","ref":"git rev-parse HEAD","quote":"09b9d8d01646ca0f2faeb273bbf227aaa9c43fb3"},"verdict":"pass"},
{"case":"adherence: tape.log and notes.md present in build run folder","rung":2,"evidence":{"kind":"file","ref":"runs/20261116T231553Z-handoff-muse-code-muse-wonder-1.0-c1/","quote":"notes.md"},"verdict":"pass"},
{"case":"adherence: no hand-edited state","rung":1,"evidence":{"kind":"ledger","ref":"exp-mvp-1-link-claim ledger","quote":"{\"ts\":\"2026-11-16T19:12:07Z\",\"edge\":\"create\",\"from\":\"\",\"to\":\"todo\",\"cycle\":1,\"commit\":null,\"verdict\":null,\"reason\":\"\",\"harness\":\"unknown\",\"model\":\"unknown\",\"bp3_version\":\"0.2.0\",\"exp_type\":\"default\"}"},"verdict":"pass"}
]
```
