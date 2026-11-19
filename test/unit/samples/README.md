# Samples (test-pyramid unit.3, red-ink R8)

Real node ledgers frozen as unit-test inputs, one per era. Copied
verbatim from the bp3 storage refs on 2026-11-19; checked for home
paths, session ids and emails (none present). A sample is adopted
test data, not a run's `tape.log` (that is verbatim evidence and is
never parsed).

| File | Source ref : path | Era |
|---|---|---|
| exp-era.ledger.jsonl | bp3/quest/2026-11-07-bp3-mvp-engine-core : docs/quests/2026-11-07-bp3-mvp-engine-core/experiments/exp-3-fsm/ledger.jsonl | exp- ids, submit/review/check edges, `submitted` state |
| graph-era.ledger.jsonl | bp3/node/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/node-followup-5-pure-grade : docs/graphs/.../nodes/node-followup-5-pure-grade/ledger.jsonl | graph era, four cycles, two blocks, combined grade casts |
| quest-era.ledger.jsonl | bp3/node/2026-11-18-test-pyramid/node-seam-2-listruns-nowait : docs/quests/2026-11-18-test-pyramid/nodes/node-seam-2-listruns-nowait/ledger.jsonl | quest era, one round |
