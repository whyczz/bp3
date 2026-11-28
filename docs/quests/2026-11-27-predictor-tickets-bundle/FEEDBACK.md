# Feedback — `2026-11-27-predictor-tickets-bundle`

Audited: `2026-11-27` on `quest/2026-11-27-predictor-tickets-bundle` (`de4719ba`, 2/2 nodes landed on cycle 1) using `v0.13.0` `bp3 warden` from `master` (`4b68dc65`).

## Human post-land feedback

- Pending owner post-land check-in.
- Release dry-run check (`./bin/bp3 release 2026-11-27-predictor-tickets-bundle --dry-run`) surfaced `E_MERGE_CONFLICT` on `test/skills.sh` against `master` (`4b68dc65`, `v0.13.0`), because `2026-11-26-warden-planned-gates` appended assertions at the end of `test/skills.sh` after this branch forked off `ae0d9bf1`. Rebase/merge onto `master` resolves cleanly in one additive hunk before promotion (`v0.13.1`, `release_kind: github`).

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-27-predictor-tickets-bundle --format json`

- `sessions_scanned`: `3` (`31a4f5cb` author + 2 cold graders `4f70ff9f`, `756298c8`)
- `planned_gates`: `[]` (`0` `--kind human-gate` nodes in this quest)
- `human_turns_count`: `75` *(see `human-log` dogfood note below — unclipped multi-quest session count)*
- `by_layer`: `git: 0`, `session: 0` (`total: 0`)
- `by_rule`: `{}`

### Audited findings

| Rule | Layer | Sev | Node | Cycle | Observed | Evidence ref | Audit |
|---|---|---|---|---|---|---|---|
| *(none)* | — | — | — | — | `0` findings | — | Clean run (`2/2` c1 ships, `brief_verbatim: 2/2`, `author_wall_s: 329s`, `grade_wall_s: 294s`) |

## Human-involvement patterns

Commands:
- `./bin/bp3 warden human-log 2026-11-27-predictor-tickets-bundle --format json`
- `./bin/bp3 warden query 31a4f5cb-15ea-4a18-b348-12b31d9d0b01 --around 1684 --window 3 --format table`
- `./bin/bp3 warden human-log --session 31a4f5cb-15ea-4a18-b348-12b31d9d0b01 --limit 100 --format table`

- **Observed human turns for this quest (`31a4f5cb`):** zero mid-build interruptions (`#1684` asked to bundle tickets `#7..#11a` and frame `#12`; `#1704` answered the 3 `ask_question` design calls for the companion quest and gave go; `#1897` asked to run the new `v0.13.0` `/warden`).
- **Live `v0.13.0` parser mismatch caught by dogfooding `warden` + `human-log`:**
  1. `bp3 warden` reported `human_turns_count: 75` while `bp3 warden human-log` returned `1` turn (`#1897`), because `count_quest_human_turns_fast` (`src/warden/warden_io.ml:362-393`) counts the whole multi-quest session `31a4f5cb` without `min_ts` filtering.
  2. `discover_quest_sessions` (`src/warden/warden_io.ml:341-347`) pinned `min_ts` to `earliest(quest-sessions/<q>.jsonl) - 120s` (`ts: 1795829722`, `20:35` `induct`), clipping earlier planning turns (`#1684`, `#1704`, framed before `v0.13.0` hooks landed at `20:34`) instead of taking `min(earliest_event, first_mention_ts) - 120s`.

## Proposals (`<= 3`)

| # | Tier | Proposal | Evidence ref | Target files |
|---|---|---|---|---|
| 1 | Small fix (deterministic) | Align `count_quest_human_turns_fast` with `human-log`'s `min_ts` cutoff and compute `min_ts = min(earliest_event, first_mention_ts) - 120s` in `discover_quest_sessions`, with unit regression tests in `test/unit/test_warden.ml`. | `bp3 warden` (`human_turns_count: 75`) vs `bp3 warden human-log` (`1` turn, clipped `#1684`/`#1704`); `src/warden/warden_io.ml:341-393` | `src/warden/warden_io.ml`, `test/unit/test_warden.ml` |
| 2 | Small fix (deterministic tests + 1-line diagram sync) | Tighten `test/skills.sh` (assert `"flash"` on the mechanical delta re-grade bullet and `Internals: layout` ordering before `Internals: names`), add whitespace-only `## Acceptance test` render test in `test/unit/test_brief.ml`, and add `[wait: owner LGTM]` to the round-shape diagram at `skills/red-ink/SKILL.md:169` (pruning check: 1-line edit in existing ASCII diagram, net `+0` lines; no redundant lines in `skills/red-ink/SKILL.md` to cut). | Cold graders `756298c8` (`skills.1` follow-ups) & `4f70ff9f` (`brief.1` follow-up) | `test/skills.sh`, `test/unit/test_brief.ml`, `skills/red-ink/SKILL.md` |

## Owner disposition

| # | Decision | Ref |
|---|---|---|
| 1 | pending owner disposal | — |
| 2 | pending owner disposal | — |
