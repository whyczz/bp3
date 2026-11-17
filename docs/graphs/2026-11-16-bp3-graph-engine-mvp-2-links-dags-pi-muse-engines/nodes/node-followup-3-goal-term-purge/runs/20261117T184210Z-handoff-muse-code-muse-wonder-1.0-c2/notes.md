# followup.3 goal-term-purge cycle 2 — run notes

- Link claimed: run_id 20261117T184210Z-handoff-muse-code-muse-wonder-1.0-c2 (as expected). Run folder did not pre-exist.
- Two commits: aea6e43 (engine fold + migration script + test updates + this graph's live-doc purge; make check green), then the migration commit (this handoff's bound commit).
- Engine: canonical docs/graphs, GRAPH.md, nodes/, node- IDs, bp3/graph + bp3/node refs. Legacy spellings fold in one place (src/graph/store.ml): branch resolution, ledger-path fallback, exp->node ID map on read. Landed ledger text never edited: migration shows ledger.jsonl as 100% renames, 0 content changes.
- Migration: scripts/migrate-graph-rename.sh --dry-run prints the full plan (373 lines, 147 branch renames); --apply refuses tracked-source-dirty trees, preserves every branch tip, re-points references, moves untracked run residue with its node. Second dry-run: no moves (idempotent).
- Grep proof: this graph's live docs 0 hits (-i -w, excluding runs/, ledger.jsonl, this record's history quotes). Live code/skills/CLI: only the named fold, the migration script's rename table, the naming-skill fold note, and negative-absence test assertions remain. Exemptions named in NODE.md '## Grep scope (cycle 2)'.
- Skills: repo tests settle bp3g as the one conducting family and assert old quest/induct/traverse names render nowhere, so no duplicate skill bodies were created; renders regenerated with bp3 skills install --harness=all.
- Verify: make check green before and after migration. All 18 nodes read back same state/commit/cycle under node- IDs (deps re-mapped). Old ID exp-followup-3-goal-term-purge still reads via the fold. Post-migration conduct (graph + node reads) ok:true, zero rename-caused refusals.
- Lesson: a rename needs three spellings kept apart — canonical writes, one fold for frozen history, and a mechanical script for the tree — or every caller becomes its own compat layer.
