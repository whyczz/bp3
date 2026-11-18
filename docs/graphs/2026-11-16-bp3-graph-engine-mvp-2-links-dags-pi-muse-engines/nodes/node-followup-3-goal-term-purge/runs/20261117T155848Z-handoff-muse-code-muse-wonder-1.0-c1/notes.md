# followup.3 goal-term-purge — run notes

- Container is now **goal**: `docs/quests/` -> `docs/goals/`, `QUEST.md` -> `GOAL.md`, engine scaffold `GRAPH.md` -> `GOAL.md`, `quest/<slug>` work branches -> `goal/<slug>` (checked-out `quest/2026-11-16-...` renames at land), storage refs `bp3/quest/` -> `bp3/goal/`.
- Ledger keys: new create lines write `goal_type`; `graph_fin` -> `goal_fin` (`node_fin` unchanged). Fold compat lives in exactly one place (`src/graph/store.ml`): legacy `quest_type`/`graph_type` keys and frozen `bp3/quest/` refs still read; landed `ledger.jsonl` text never rewritten.
- Exemptions to grep-zero (named): landed ledger lines, run artifacts under `runs/`, negative-absence assertions in tests (old door/skill must refuse), rename-table history quotes in GOAL.md/EXPERIMENT.md records, and the one fold-compat mapping above.
- `graph` stays: it names the goal's DAG (`bp3 g` unchanged); graph id/slug unchanged. AGENTS.md + naming skill synced; no stale anti-graph rule found (rule now teaches goal+graph).
- Verify: `make check` + post-purge `bp3 g r` conduct with zero rename-caused refusals (see tape.log).
