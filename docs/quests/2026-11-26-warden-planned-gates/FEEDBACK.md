# Feedback — `2026-11-26-warden-planned-gates`

Audited: `2026-11-27` on `quest/2026-11-26-warden-planned-gates` (`6674d0cd`, 4/4 nodes landed on cycle 1).

## Human post-land feedback

- Pending owner post-land check-in (captured during `/red-ink` before `induct` via `bp3 warden human-log`):
  - Two `/red-ink` stops (`#1571`, `#1590`) flagged undefined insider jargon (`Layer-2 human_steer`, `human steer handle`, `planned`); ticket `#4` shipped the inline-jargon rule (`c04780cc` + `bp3-yap-skills` `300ae49`).
  - Owner pushback at `#1609–1610` killed `--planned` on `e block` completely in favor of existing `--kind human-gate` (`v0.11.0`), cutting CLI and ledger complexity in half.

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-26-warden-planned-gates --format json`

- `sessions_scanned`: `5` (`661e5fe6` author + 4 cold graders `33b37bb0`, `c023bf9f`, `7193a8b5`, `fce4e08a`)
- `planned_gates`: `[]` (`0` `--kind human-gate` nodes in this quest)
- `human_turns_count`: `52`
- `by_layer`: `git: 0`, `session: 1` (`total: 1`)
- `by_rule`: `context_bloat: 1`

### Audited findings

| Rule | Layer | Sev | Node | Cycle | Observed | Evidence ref | Audit |
|---|---|---|---|---|---|---|---|
| `context_bloat` | `session` | `minor` | `node-skills-1-document-human-gate-and-full-session-warden` | `c1` | `498k tok (5 turns)` (`> 400k agy`) | `tx:/Users/whycz/.gemini/antigravity-cli/brain/661e5fe6-6755-40e1-9f05-f4b4cab29c4a/.system_generated/logs/transcript.jsonl#step:1823` | **TP** — session `661e5fe6` ran 4 earlier quests + `/red-ink` + all 4 nodes without compacting before `skills.1`. |

### Human-involvement patterns (`human-log` / `query` dogfood)

Commands: `./bin/bp3 warden human-log 2026-11-26-warden-planned-gates --format table` and `./bin/bp3 warden query 661e5fe6-6755-40e1-9f05-f4b4cab29c4a --around 1571|1590 --window 2`

- **Jargon stops in `/red-ink` (`#1571`, `#1590`):** Owner paused twice when options used undefined internal terms (`layer 2 human steer`, `human steer handle`, `planned`). Already addressed by ticket `#4` (inline jargon definitions).
- **Live parser gaps caught by dogfooding `human-log` on session `661e5fe6`:**
  1. `agy` wraps `USER_INPUT` in `<USER_REQUEST> ... </USER_REQUEST> <ADDITIONAL_METADATA> ... </ADDITIONAL_METADATA>`, causing `/compact` turns (`#615`, `#1425`) to bypass the `/compact` skip filter and adding XML boilerplate to every table row.
  2. Multi-quest session `661e5fe6` included 33 turns from earlier quests (`#0..1476`) before `#1560` ever mentioned `2026-11-26-warden-planned-gates`, all tagged `red-ink` by the retroactive fallback.

## Proposals (`<= 3`)

| # | Tier | Proposal | Evidence ref | Target files |
|---|---|---|---|---|
| 1 | Small fix (deterministic) | Unwrap `<USER_REQUEST>...</USER_REQUEST>` & strip `<ADDITIONAL_METADATA>` in `Agy_tx.parse_interactions` before the `/compact` filter and `clip`, and add `&& str "output" j = ""` to `Agy_tx.query_window:394` so `PLANNER_RESPONSE` with `output` classifies as `"assistant"`. | `human-log` `#615`, `#1425`, `#1560`; cold grader `c023bf9f` on `src/quest/agy_tx.ml:394` | `src/quest/agy_tx.ml`, `test/unit/test_agy_tx.ml` |
| 2 | Small fix (deterministic) | Bound quest `human-log` turns in multi-quest sessions to start at the session's first quest touch (`first_event_ts` or first step mentioning `<q>`), skip leading flags in `Hooks.extract_quest_phase_from_segment` for `bp3 warden --format json <q>`, and exercise `Warden.assign_phase` inside the QCheck2 property. | `human-log` `#0..1476` pre-quest leakage in `661e5fe6`; cold graders `c023bf9f` (`hooks.ml:303-307`) & `7193a8b5` (`test_warden.ml:527-544`) | `src/warden/warden_io.ml`, `src/quest/hooks.ml`, `test/unit/test_warden.ml`, `test/unit/test_hooks.ml` |
| 3 | Small fix (prose + pruning check) | Add `Human-involvement patterns` to the `FEEDBACK.md` sections list in `skills/warden/SKILL.md:87-96`, and prune duplicate `human-log`/`<= 3 proposals` phrasing in lines `67-72` (net `<= 0` lines). | Cold grader `fce4e08a` (`skills.1` `NODE.md:75` vs `skills/warden/SKILL.md:87-96`) | `skills/warden/SKILL.md` |

## Owner disposition

| # | Decision | Ref |
|---|---|---|
| 1 | `applied` | `3c78fe30` |
| 2 | `applied` | `3c78fe30` |
| 3 | `applied` | `3c78fe30` |
