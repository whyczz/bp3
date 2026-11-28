# Feedback — `2026-11-27-declarative-json-quest-init`

Audited: `2026-11-27` on `quest/2026-11-27-declarative-json-quest-init` (`444366e5`, 3/3 nodes landed, 4 cold grades) using `v0.13.0` `bp3 warden` from `master` (`4b68dc65`).

## Human post-land feedback

- Pending owner post-land check-in.
- Release dry-run check (`./bin/bp3 release 2026-11-27-declarative-json-quest-init --dry-run`) surfaced `E_MERGE_CONFLICT` on `test/skills.sh` against `master` (`4b68dc65`, `v0.13.0`). Quest 2 is stacked on `quest/2026-11-27-predictor-tickets-bundle` (`de4719ba`); once Quest 1 rebases/promotes onto `master` (`v0.13.1`), Quest 2 rebases cleanly onto it (`v0.14.0`, `release_kind: github`).

## Warden deterministic summary

Command: `./bin/bp3 warden 2026-11-27-declarative-json-quest-init --format json`

- `sessions_scanned`: `5` (`31a4f5cb` author + 4 cold graders `e7acbd81`, `81439908`, `bafff8a3`, `f331bbfe`)
- `planned_gates`: `[]` (`0` `--kind human-gate` nodes in this quest)
- `human_turns_count`: `75` *(same unclipped multi-quest session count noted in Quest 1 `FEEDBACK.md`)*
- `by_layer`: `git: 2`, `session: 1` (`total: 3`)
- `by_rule`: `grade_inversion: 2`, `context_bloat: 1`

### Audited findings

| Rule | Layer | Sev | Node | Cycle | Observed | Evidence ref | Audit |
|---|---|---|---|---|---|---|---|
| `grade_inversion` | `git` | `major` | `node-skills-1-json-quest-skills-and-completions` | `c0` (node rollup) | `grade 246s vs author 155s (1.59x)` (`> 180s & > 1.5x`) | `metrics:node-skills-1-json-quest-skills-and-completions` + `tx:f331bbfe#13,#14,#32,#35,#41` | **TP** — grader ran `./scripts/receipt` (`task-13`) and `bp3 skills install` (`task-14`) concurrently in the same grade desk; `task-13` exited `1` (`#32`), forcing two extra full runs (`task-35`, `task-41`, `+127s`). |
| `grade_inversion` | `git` | `major` | `node-spec-1-json-quest-schema-and-brief` | `c0` (node rollup) | `grade 30694 vs author 27163 tok_out` (`> 25k & grade > author`) | `metrics:node-spec-1-json-quest-schema-and-brief` (`c1: 16435`, `c2: 14259` vs author `c1: 23671`, `c2: 3492`) | **TP** — `c2` mechanical delta re-grade (`81439908`) ran on `"inherit"` instead of `"flash"` because Ticket `#11a` (Quest 1 `e3eeb5b7`) was not yet promoted/installed globally. Already addressed once Quest 1 lands & installs. |
| `context_bloat` | `session` | `minor` | `node-skills-1-json-quest-skills-and-completions` | `c1` | `499k tok (4 turns)` (`> 400k agy`) | `tx:/Users/whycz/.gemini/antigravity-cli/brain/31a4f5cb-15ea-4a18-b348-12b31d9d0b01/.system_generated/logs/transcript.jsonl#step:1886` | **TP** — author session `31a4f5cb` ran two prior quests + framing + all 5 nodes across both quests before compacting at `#1899`. |

## Human-involvement patterns

Commands:
- `./bin/bp3 warden human-log 2026-11-27-declarative-json-quest-init --format json`
- `./bin/bp3 warden query 31a4f5cb-15ea-4a18-b348-12b31d9d0b01 --around 1704 --window 3 --format table`
- `./bin/bp3 warden query f331bbfe-2a3f-4c7e-9f00-32c6120f35a7 --around 13,38 --window 8 --format table`

- **Observed human turns (`31a4f5cb`):** clean upfront design alignment — `#1684` triggered `/quest` on Ticket `#12`; `#1704` settled all 3 `ask_question` choices in one turn (`bp3 q c --file`, `quest.json` single source of truth + `--scaffold`, `Research`/`Explore` todo-only JSON diff guard); zero mid-induct human interrupts across 3 nodes / 4 grades.
- **Live `v0.13.0` hook leakage caught on disk:** `.git/bp3/quest-sessions/five-kinds.jsonl` (`sid: bafff8a3`, `init.1` cold grader) leaked into the real repo's `.git/bp3/quest-sessions/` when `Hooks.record_quest_session` parsed a scratch test command (`bp3 q c five-kinds`) without checking whether the quest exists in the repo; additionally, read-only `bp3 q r` after `bp3 warden` appended `phase: "induct"` after `phase: "fin"` in `2026-11-27-declarative-json-quest-init.jsonl`.

## Proposals (`<= 3`)

| # | Tier | Proposal | Evidence ref | Target files |
|---|---|---|---|---|
| 1 | Small fix (deterministic + 1-line rule) | Serialize `scripts/receipt` with an exclusive desk lock (or fail fast with clear concurrent-runner hint) and add 1 line under `GRADING.md` `## Gate` (*"Run `./scripts/receipt` alone in the grade desk; never run `bp3 skills install` or `dune` concurrently with it"* — pruning check: lines 10–13 of `GRADING.md` are 4 dense lines with no redundant text to delete, net `+1` line) to kill parallel grade-desk build collisions. | `metrics:node-skills-1-json-quest-skills-and-completions` (`grade_inversion` `246s vs 155s`); `tx:f331bbfe#13,#14,#32,#35,#41` | `scripts/receipt`, `GRADING.md` |
| 2 | Small fix (deterministic) | Guard `Hooks.record_quest_session` so it only appends to `.git/bp3/quest-sessions/<q>.jsonl` when `<q>` exists in the current repo (ledger branch or `docs/quests/<q>/{QUEST.md,quest.json}`) and does not downgrade `"fin"` back to `"induct"` on read-only `bp3 q r`, with unit tests in `test/unit/test_hooks.ml`. | `.git/bp3/quest-sessions/five-kinds.jsonl` (`bafff8a3` fixture leak) & `2026-11-27-declarative-json-quest-init.jsonl` (`fin -> induct` inversion) | `src/quest/hooks.ml`, `test/unit/test_hooks.ml` |
| 3 | Small fix (deterministic) | Close the 3 non-blocking `quest.json`-only edge cases flagged by cold grader `bafff8a3`: fall back to sibling `quest.json` in `scripts/check-bump` when an authored `QUEST.md` omits `bump:`, emit `Quest: docs/quests/<q>/quest.json` in `src/quest/release_io.ml` notes when `QUEST.md` is absent, and assert `q c demo "--"` completions directly in `test/completion.sh`. | Cold grader `bafff8a3` (`init.1` follow-ups) | `scripts/check-bump`, `src/quest/release_io.ml`, `test/completion.sh` |

## Owner disposition

| # | Decision | Ref |
|---|---|---|
| 1 | pending owner disposal | — |
| 2 | pending owner disposal | — |
| 3 | pending owner disposal | — |
