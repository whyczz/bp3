# 2026-11-23-dag-fsm-v2 — Post-Quest Feedback & Warden Audit

## Human post-land feedback

- Inducted unattended via `/induct-yolo` (back-to-back ahead of `2026-11-23-dag-contracts`); owner reviewed check-in report and directed `warden both, apply proposals` on 2026-11-26.
- All 3 nodes (`fsm.1`, `ancestry.1`, `skills.1`) passed diligence gate on cycle 1; live scratch demo verified (`demo/demo.sh`, recorded to `demo/demo.cast`).

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-23-dag-fsm-v2` (from stacked quest desk; `sessions_scanned: 4`, `total: 2`, `by_layer: {git: 1, session: 1}`, `by_rule: {multi_active_quest: 1, context_bloat: 1}`).

| Rule | Layer | Severity | Ref | Observed / Threshold | Audit |
|---|---|---|---|---|---|
| `multi_active_quest` | git | major | `repo:QUEST.md` | 2 active quests (`> 1`) | **TP (expected)** — both stacked quests were `status: active` while awaiting promotion; clears automatically on `bp3 release` |
| `context_bloat` | session | minor | `tx:...transcript.jsonl#step:1372` | `416k tok (11 turns)` on `skills.1` c1 (`> 400k agy`) | **TP** — back-to-back framing + induction in one un-compacted session; `/compact` between stacked quests prevents it |

Additional cited evidence from `metrics scrape` and cold graders:
- `metrics:node-fsm-1-collapse-verify-and-auto-land`: `brief_edited: 1` on c1 from `jq -r .brief` stripping trailing newline (fixed via `jq -j .brief`, yielding `brief_verbatim: 1` on every subsequent grade).
- `git:f83811cb`, `git:4efc7880`: dead `Names.edge_verify` constant left in `src/quest/names.ml` and stale `verify` edge / retired-door wording left in `skills/naming/SKILL.md`.

## Proposals (<= 3)

| # | Proposal | Evidence ref | Target files | Pruning check |
|---|---|---|---|---|
| P1 | Remove unused `Names.edge_verify` and sync `skills/naming/SKILL.md` to v2 doors/kinds/edges (drop retired `verify`, add `approve`/`iterate`) | `git:f83811cb`, `git:4efc7880` | `src/quest/names.ml`, `skills/naming/SKILL.md` | Deletes dead constant `edge_verify`, retired `verify` edge, and stale `"retired bp3 q door refuses"` typo |
| P2 | Note `jq -j .brief` (not `jq -r`) in `skills/induct/SKILL.md` so rendered briefs stay byte-verbatim | `metrics:node-fsm-1-collapse-verify-and-auto-land` | `skills/induct/SKILL.md` | Single inline parenthetical; existing `test/skills.sh` verbatim check untouched |
| P3 | Operational discipline (no code change): run `/compact` between back-to-back quests; promote stacked quests in order | `tx:...#step:1372`, `repo:QUEST.md` | none | Zero prose or code added |

## Owner disposition

*(Applied on `quest/2026-11-23-dag-contracts` stacked atop this branch to keep `quest/2026-11-23-dag-fsm-v2` bound SHAs untouched and zero-conflict on `bp3 release`.)*

| # | Disposition |
|---|---|
| P1 | `applied 2c948366` |
| P2 | `applied 2c948366` |
| P3 | `skipped` (operational note; clears on release + `/compact`) |
