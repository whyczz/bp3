# Handoff lessons — node-followup-3-goal-term-purge cycle 5 (run 20261117T235053Z-handoff-muse-code-muse-wonder-1.0-c4)

- Claimed link `bp3link_cbd0181acfa7c3848a8fb7cbc42f58d8`; returned run_id matched the expected folder name. Run folder did not pre-exist.
- Named fix applied at the source: `skills/naming/SKILL.md` Artifacts now lists `GRAPH.md`. Same-class sweep (`git grep GOAL.md` on live surfaces) found four more stale owners — `skills/using-bp3/SKILL.md` (2), `skills/bp3g-no-human/SKILL.md`, `skills/bp3g/workflows/bp3g-grade.js`, `CLAUDE.md` (2, now identical to `AGENTS.md`) — all fixed to `GRAPH.md`. Exempt left alone: landed ledger/fix-ledger history quotes, this record's pseudocode, and the migration script's rename table.
- Renders regenerated with `./bin/bp3 skills install --harness=all`; never hand-edit `.pi/.claude/.agents` renders.
- Lesson: each cycle fixed only the files the last grade named (cycle 4: GRAPH.md index + AGENTS.md) and left the same token one file over. Grep the exact old token across every live owner before handoff; `make check` does not cover doc term sync.
- Clean-tree handoff: outstanding cycle-3 run `notes.md` files committed verbatim (tape.log stays gitignored), same as the cycle-4 fix commit.
