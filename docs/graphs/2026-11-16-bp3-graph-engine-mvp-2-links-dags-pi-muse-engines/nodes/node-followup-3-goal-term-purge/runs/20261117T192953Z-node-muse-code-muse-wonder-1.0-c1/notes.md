# Audit notes — node-followup-3-goal-term-purge @ bd58f824 (cycle 2)

## Lessons

- Bound commit bd58f824 is HEAD; scope C is gated here (unlike c0ab195): GRAPH.md/NODE.md, docs/graphs + nodes/, node- IDs, migration script, bp3g skill family.
- Grep-zero holds only under the named cycle-2 scope: live code/skills hits are exactly the exempt fold (src/graph/store.ml), the migration script rename table, and the naming-skill fold note; this graph's live docs grep clean once this record's history quotes are excluded (git grep exit 1, empty stdout).
- Migration dry-run post-apply prints only the re-point plan line plus the idempotent no-op line (2 lines) — a second run is a no-op; ledger.jsonl moves are 0-insertion/0-deletion renames.
- Fresh `make check` green (make-check-pipe-status:0, pi-tree 13/13); conduct read shows node-followup-3-goal-term-purge handed_off at the bound commit with zero rename-caused refusals. No whole-tape (rung 5b) read; verdicts decided at rungs 2-3.

## Matrix

```json
[
  {"case": "files renamed", "rung": 2, "evidence": {"kind": "command", "ref": "git ls-tree --name-only bd58f824c35c001287882dcacf6a3b708f3aa77e docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-3-goal-term-purge/", "quote": "docs/graphs/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/nodes/node-followup-3-goal-term-purge/NODE.md"}, "verdict": "pass"},
  {"case": "code renamed", "rung": 3, "evidence": {"kind": "command", "ref": "make check", "quote": "make-check-pipe-status:0"}, "verdict": "pass"},
  {"case": "skills renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check", "quote": "{\"ok\":true,\"fresh\":[\"node-loop\",\"bp3g-grade\",\"bp3g-land\",\"bp3g-node\"]}"}, "verdict": "pass"},
  {"case": "grep proof", "rung": 3, "evidence": {"kind": "grep", "ref": "git grep -i -w -n quest bd58f824c35c001287882dcacf6a3b708f3aa77e -- src/ bin/ scripts/ extensions/ skills/", "quote": "else if ref_tip (\"refs/heads/bp3/quest/\" ^ q) <> None then \"refs/heads/bp3/quest/\" ^ q"}, "verdict": "pass"},
  {"case": "conduct survives", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261117T192953Z-node-muse-code-muse-wonder-1.0-c1 ./bin/bp3 g r 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines", "quote": "\"node\":\"node-followup-3-goal-term-purge\",\"state\":\"handed_off\",\"fin\":null,\"cycle\":1,\"commit\":\"bd58f824c35c001287882dcacf6a3b708f3aa77e\""}, "verdict": "pass"},
  {"case": "terms synced", "rung": 2, "evidence": {"kind": "file", "ref": "skills/naming/SKILL.md:35 (at bd58f824c35c001287882dcacf6a3b708f3aa77e)", "quote": "- Goal and graph: the container of work is a **goal** (`docs/graphs/<goal>/GRAPH.md`, `goal/<slug>` branch, finish word `goal_fin`); its DAG of nodes is the **graph** (`bp3 g` unchanged). Graph id/slug unchanged by the goal rename."}, "verdict": "pass"}
]
```
