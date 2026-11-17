# mig.1 handoff-verbs — audit notes (run 20261116T193614Z-audit-muse-code-muse-wonder-1.0-c1)

## Lessons
- Compat lives exactly where EXPERIMENT.md promised: one fold site in Store (fold_edge/fold_state_name); every other old-word hit in src is that site. test/q.sh old words are frozen-ledger fixtures + refusal loop, not identifiers.
- Strongest proof was rung 3, not prose: `make check` exit 0 (q/skills/harness/pi suites) plus live `bp3 q ... r` reads — old quest 2026-11-14-bp3-workflows-v2 still folds submit/submitted ledgers to landed with identical commits, and this exp reads handed_off on the bound commit.
- Mixed-vocab survival is visible in the artifacts themselves: build Run folder is named `...-submit-...` while its ledger edge already writes `handoff`/`handed_off` — one fold reads both, by design.
- Renders are generated, not hand-edited: harness copies differ from skills/ sources only by the GENERATED header line; HEAD diff touches zero docs/quests paths and no ledger/state files.
- No rung-5 tape read was needed; every row decided at rungs 2-3.

## Evidence matrix
```json
[
{"case":"old quest reads identically","rung":3,"evidence":{"kind":"command","ref":"./bin/bp3 q 2026-11-14-bp3-workflows-v2 r","quote":"{\"exp\":\"exp-1-induct-grade\",\"state\":\"landed\",\"fin\":\"exp_fin\",\"cycle\":1,\"commit\":\"b415f4a323975eb5162626b85a7c00ae59d5153f\"}"},"verdict":"pass"},
{"case":"new verbs round-trip","rung":3,"evidence":{"kind":"command","ref":"make check (./test/q.sh)","quote":"q tests: ok"},"verdict":"pass"},
{"case":"compat in one place","rung":2,"evidence":{"kind":"grep","ref":"grep -rn fold_edge/fold_state_name src/quest/store.ml:156-160","quote":"let fold_edge = function | \"submit\" -> \"handoff\" | \"review\" -> \"grade\" | \"check\" -> \"verify\"; let fold_state_name = function \"submitted\" -> \"handed_off\" | s -> s"},"verdict":"pass"},
{"case":"conducting surfaces updated","rung":3,"evidence":{"kind":"command","ref":"make check","quote":"skills tests: ok (115 assertions); MAKE_EXIT:0"},"verdict":"pass"},
{"case":"this quest survives itself","rung":3,"evidence":{"kind":"command","ref":"./bin/bp3 q 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines r exp-mig-1-handoff-verbs","quote":"{\"state\":\"handed_off\",\"cycle\":1,\"commit\":\"44196725860125de048415ff6a4be350a90c033b\",\"legal_edges\":[\"grade\",\"verify\",\"block\",\"delete\"]}"},"verdict":"pass"},
{"case":"adherence: handoff edge called by the child directly","rung":2,"evidence":{"kind":"ledger","ref":"exp ledger handoff line (bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mig-1-handoff-verbs:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mig-1-handoff-verbs/ledger.jsonl)","quote":"{\"ts\":\"2026-11-16T19:34:49Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"44196725860125de048415ff6a4be350a90c033b\",\"verdict\":null,\"reason\":\"FSM verbs renamed to handoff/grade/verify; compat fold in store\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261116T191513Z-submit-muse-code-muse-wonder-1.0-c1\"}"},"verdict":"pass"},
{"case":"adherence: env-set run-id stamped by bp3","rung":2,"evidence":{"kind":"ledger","ref":"exp ledger handoff line (same as above)","quote":"\"run_id\":\"20261116T191513Z-submit-muse-code-muse-wonder-1.0-c1\" (corroborated by <git-common-dir>/bp3/run-lifecycle-derivations/20261116T191513Z-submit-muse-code-muse-wonder-1.0-c1.jsonl init_record with same run_id)"},"verdict":"pass"},
{"case":"adherence: clean commit","rung":2,"evidence":{"kind":"command","ref":"git status --short (empty) && git log -1","quote":"44196725860125de048415ff6a4be350a90c033b feat(mig.1): rename FSM verbs to handoff/grade/verify"},"verdict":"pass"},
{"case":"adherence: tape.log and notes.md present in build run folder","rung":2,"evidence":{"kind":"file","ref":"docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mig-1-handoff-verbs/runs/20261116T191513Z-submit-muse-code-muse-wonder-1.0-c1/","quote":"notes.md tape.log (tape.log 339 lines)"},"verdict":"pass"},
{"case":"adherence: no hand-edited state","rung":2,"evidence":{"kind":"command","ref":"git diff --name-only HEAD~1 HEAD | grep -ci docs/quests; diff skills/induct/SKILL.md .agents/skills/induct/SKILL.md","quote":"0 quest paths in HEAD diff; renders differ only by: <!-- GENERATED from skills/induct/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->"},"verdict":"pass"}
]
```
