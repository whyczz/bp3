# 2026-11-23-dag-contracts — Post-Quest Feedback & Warden Audit

## Human post-land feedback

- Inducted unattended via `/induct-yolo` stacked on `2026-11-23-dag-fsm-v2`; owner directed `warden both, apply proposals` on 2026-11-26.
- All 3 nodes (`kinds.1` c2, `research.1` c1, `skills.1` c1) passed diligence gate with `brief_verbatim: 4, brief_edited: 0`; live scratch demo verified (`demo/demo.sh`, recorded to `demo/demo.cast`).
- Incoming cross-repo ticket #3 (`predictor -> bp3`: distinguish planned owner gates from `human_steer`) is now structurally addressed by `--kind human-gate` (`e approve`), ready to close once released to `$PREFIX`.

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-23-dag-contracts` (`sessions_scanned: 5`, `total: 2`, `by_layer: {git: 1, session: 1}`, `by_rule: {multi_active_quest: 1, context_bloat: 1}`).

| Rule | Layer | Severity | Ref | Observed / Threshold | Audit |
|---|---|---|---|---|---|
| `multi_active_quest` | git | major | `repo:QUEST.md` | 2 active quests (`> 1`) | **TP (expected)** — stacked on `2026-11-23-dag-fsm-v2`; clears on sequential `bp3 release` |
| `context_bloat` | session | minor | `tx:...transcript.jsonl#step:1466` | `499k tok (21 turns)` on `kinds.1` c1 (`> 400k agy`) | **TP** — peaked just before auto-compaction; post-compaction `research.1` and `skills.1` stayed well under threshold |

Additional cited evidence from cold graders:
- `git:670461a0` (grader `e889cc33`): `Render.commit_changes` (`src/quest/render.ml:12`) still omitted `-m --first-parent --root` on `git diff-tree`, leaving `changes` empty on `--no-ff` merge commits.
- `git:bc2a4ba9`, `git:9c6ed725` (graders `3ef0dba5`, `37bcfb67`): `test/g.sh` lacked an explicit `--outcome missed` test and `test/completion.sh` only tested `c new-node "--"` flag completion in bash (not zsh).

## Proposals (<= 3)

| # | Proposal | Evidence ref | Target files | Pruning check |
|---|---|---|---|---|
| P1 | Pass `-m --first-parent --root` to `git diff-tree` in `Render.commit_changes` + add `--no-ff` merge-commit `changes` regression check | `git:670461a0` | `src/quest/render.ml`, `test/g.sh` | Deterministic code/test fix; zero prose added |
| P2 | Add `--outcome missed` fixture check in `test/g.sh` and mirror `c new-node "--"` flag-prefix trace in zsh block of `test/completion.sh` | `git:bc2a4ba9`, `git:9c6ed725` | `test/g.sh`, `test/completion.sh` | Deterministic test coverage only; zero prose added |
| P3 | Freeze `explore_quality` Warden middleware (checks `REPORT.md`, target, outcome, edge cases/lessons on landed `Explore` nodes without policing exploration tokens) until >= 3 real `Explore` nodes run | `docs/quests/2026-11-23-dag-contracts/QUEST.md` | `docs/icebox/2026-11-26-warden-explore-quality.md` | Frozen in icebox instead of premature code |

## Owner disposition

| # | Disposition |
|---|---|
| P1 | `applied 13e592ff` |
| P2 | `applied 13e592ff` |
| P3 | `icebox docs/icebox/2026-11-26-warden-explore-quality.md` (`120d0079`) |
