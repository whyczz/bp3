---
status: proposed
home_repo: bp3
date: 2026-11-26
bump: minor
---

# warden-planned-gates: `human-gate` hygiene & full-lifecycle human-involvement audit (`init` -> `/red-ink` -> `induct` -> `fin`)

TL;DR
Two cleanly separated Warden upgrades in one unified quest — with zero new flags on `bp3 q`:
1. **Defect hygiene (Ticket #3):** Thread `ne_kind` (`--kind human-gate` etc., shipped in `v0.11.0`) into `Warden.node_evidence`. Treat `--kind human-gate` as the sole planned owner-gate / decision node type (`0` `human_steer` findings, surfaced visibly in `planned_gates[]`), while `e block`, cycle-cap escalations, and mid-code `USER_INPUT` stay `Major human_steer`. Also allow `bp3 warden <quest>` to succeed on proposed quests (`docs/quests/<q>/QUEST.md`) before `bp3 q c <q>` runs.
2. **Full-lifecycle human-involvement audit (`init` -> `/red-ink` -> `induct` -> `fin` + standalone sessions):** Persist a durable machine-local quest-session log (`.git/bp3/quest-sessions/<quest>.jsonl`, plus retroactive transcript-scan fallback), teach OCaml transcript parsers to extract compact human interactions (`USER_INPUT` + paired `ask_question`/`AskUserQuestion` Q&A) and bounded step drill-down windows, and expose `bp3 warden human-log` + `bp3 warden query` so `/warden` can mine recurring human friction/preferences both right after `/red-ink` and at `quest fin` into `<= 3` concrete proposals.

ELI5
Today `bp3 warden` has two opposite blind spots around humans: (1) during `induct`, it doesn't know about `--kind human-gate` decision nodes, so planned owner checkpoints weren't distinguished from surprise mid-code rescues (`e block`); and (2) during planning and `/red-ink`, Warden throws away your chat messages completely, so recurring feedback ("define jargon inline", "use typed Python") evaporates unless you file tickets by hand. This quest fixes both: expected owner pauses use existing `--kind human-gate` nodes (zero false `Major human_steer`), and `bp3 warden` reads & queries entire sessions across `init -> /red-ink -> induct -> fin` (or standalone `--session latest`) so `/warden` learns from every human turn automatically.

## Context

Origin:
- Ticket `#3` (filed from `predictor`, 2026-11-26): `predictor`'s `node-paper-8-paper-smoke` hit `Major human_steer` for an intentional AV approval + 12h overnight live smoke wait.
- Owner direction during `/red-ink` (2026-11-27):
  - Kill `--planned` on `e block` completely; use existing `--kind human-gate` (`v0.11.0`) as the sole decision / planned owner-wait node type so `e block` always unambiguously means unplanned `Major human_steer`.
  - Expand this quest to also let Warden read & query entire sessions — both standalone right after `/red-ink` (`--session <id|latest>` or proposed `<quest>`) and quest-wide from `quest init` to `quest fin` — feeding human interactions into `/warden`'s `<= 3` proposals without inflating defect `findings[]`.

Measured ground (audited 2026-11-26..27 on `master` `7f3ee886`..`caa639df`, `v0.12.0`):

| Fact | Source |
|---|---|
| `Store.node_kind` already defines `Human_gate` (`--kind human-gate`), finishing via `BP3_DECIDER=human e approve --reason "..."` | `src/quest/store.ml:87-103`, `src/quest/main.ml:410` |
| `Metrics.author_spans` picks the latest non-`resume` edge before `handoff`, so placing a `human-gate` node (`approve` at `t2`) between `smoke.1` (`handoff` at `t1`) and `smoke.3` (`handoff` at `t3`) already starts `smoke.3`'s author window at `t2` — isolating owner chat during `[t1, t2]` naturally | `src/quest/metrics.ml:167-175` |
| `Warden.node_evidence` lacks `ne_kind`; `Warden_io.load_quest` folds `Store.fold_node` and discards `s.node_kind` | `src/warden/warden.ml:38-43`, `src/warden/warden_io.ml:193-197` |
| `Main.do_warden` refuses `bp3 warden <quest>` with `E_NOT_FOUND` when `fold_quest q = None`, blocking post-`/red-ink` runs before `bp3 q c <q>` | `src/quest/main.ml:740-745` |
| `Agy_tx.parse` already reads `USER_INPUT` content and pairs `PLANNER_RESPONSE` tool calls (`ask_question`) with `GENERIC` results via `pending`, but discards the text | `src/quest/agy_tx.ml:112-159` |
| `Hooks` already binds sessions touching `docs/quests/<q>/*` or `bp3 q <q>` into `.git/bp3/sessions/<sid>.json`, but prunes them after 24h (`session_ttl_s = 86400`) and clears on `bp3 release` | `src/quest/hooks.ml:89-95` |

## Terms

| Term | Meaning |
|---|---|
| `human-gate` | existing node kind (`--kind human-gate`) for planned owner decisions/approvals; finishes via `e approve --reason` |
| `ne_kind` | `string` field on `Warden.node_evidence` (`"code" \| "direct" \| "research" \| "explore" \| "human-gate"`), loaded from `Store.node_kind_to_string s.node_kind` |
| `planned_gates` | additive JSON array in `bp3 warden` output (`[{"quest","node","kind":"human-gate","cycle","reason"}]`) auditing intentional owner gates without inflating `findings[]` |
| `human-log` | reserved `bp3 warden` subcommand returning bounded `HumanInteraction` turns across a quest (`init..fin`) or standalone session (`--session <id\|latest>`) |
| `query` | reserved `bp3 warden` subcommand (`--around <step> [--window 5]`) returning bounded surrounding steps from a session transcript |
| `quest-sessions/<q>.jsonl` | machine-local append-only log under `<git-common-dir>/bp3/quest-sessions/` written by `hooks.ml` (never committed, no 24h TTL) |
| `human_steer` | existing `Major` Warden defect rule covering unplanned `e block`, cycle-cap `to: blocked` escalations, and mid-node `USER_INPUT` on non-`human-gate` nodes |

## Inputs

| Input | Source & precedence |
|---|---|
| `bp3 warden [<quest> \| --session <id\|latest>] [--last N \| --all] [--no-sessions] [--format json\|table]` | Defect plugs + summary (`planned_gates[]`, `human_turns_count`); `<quest>` succeeds if either `bp3 q` ledger exists OR `docs/quests/<q>/QUEST.md` exists; `--session latest` resolves to the most recently updated transcript in harness dirs |
| `bp3 warden human-log (<quest> \| --session <id\|latest>) [--phase init\|red-ink\|induct\|fin] [--limit N] [--format json\|table]` | Full-session human interaction digest (default `--limit 200`); `<quest>` unions durable `.git/bp3/quest-sessions/<quest>.jsonl` + retroactive transcript scan fallback, deduped by `session_id` |
| `bp3 warden query <session-id\|latest> --around <step> [--window N] [--format json\|table]` | Bounded drill-down context window (`[step - window .. step + window]`, default `--window 5`) |
| Harness dir overrides (`--dir`/`--claude-dir`, `--pi-dir`, `--agy-dir`) | Supported identically across `warden`, `warden human-log`, and `warden query` |
| Durable quest-session log (`.git/bp3/quest-sessions/<quest>.jsonl`) | Appended by `hooks.ml` (`PostToolUse`) when `(sid, quest, phase)` changes on `docs/quests/<quest>/*` or `bp3 q <quest>` |

## Outputs

| Output | Shape |
|---|---|
| `bp3 warden [<quest>]` JSON verdict | existing schema plus `"planned_gates": [{"quest","node","kind":"human-gate","cycle","reason"}]` and `"human_turns_count": <int>` (keeps default payload compact); works on proposed quests with `QUEST.md` |
| `bp3 warden [<quest>]` table output | appends `(N planned gate(s))` to summary line when `N > 0` |
| `bp3 warden human-log (...)` | `{"ok":true,"scope":...,"sessions":[...],"interactions":[{"phase","session_id","harness","step","ts","source","agent_asked","human_said","nearby_edges"}],"truncated":bool}` (`--format json\|table`) |
| `bp3 warden query <session-id\|latest> --around <step>` | `{"ok":true,"session_id":...,"harness":...,"around":<step>,"window":<N>,"steps":[{"step","ts","role","text"}]}` (bounded excerpts `<= 2000` chars/step, `--format json\|table`) |
| Refusals (`E_USAGE` exit 2 / `E_NOT_FOUND` exit 1) | `E_USAGE` on invalid `--phase`, missing `--around`, non-positive `--limit`/`--window`, or conflicting `<quest>` + `--session`; `E_NOT_FOUND` on unknown quest or session |
| `completions/_bp3`, `completions/bp3.bash`, `bin/bp3` | advertise `human-log` and `query` (and flags) under `bp3 warden` |
| `skills/{warden,using-bp3,induct,induct-yolo}/SKILL.md` | document `--kind human-gate` vs unplanned `e block`, `planned_gates`, `bp3 warden human-log` / `query`, and standalone `/red-ink` + full-lifecycle `init..fin` `/warden` passes |

## Acceptance gates

Observed today (2026-11-27, `master` `caa639df`, `v0.12.0`):

```text
$ ./bin/bp3 warden human-log 2026-11-26-warden-planned-gates
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"bp3 warden takes at most one <quest>"},...}}
$ ./bin/bp3 warden 2026-11-26-warden-planned-gates
{"ok":false,"error":{"code":"E_NOT_FOUND","facts":{"quest":"2026-11-26-warden-planned-gates"},...}}
$ grep -n "ne_kind\|planned_gates\|quest-sessions" src/warden/warden.ml src/warden/warden_io.ml src/quest/hooks.ml
# 0 matches
```

Design trace (after quest lands):

```text
gate.1     # human-gate node -> 0 human_steer, visible in planned_gates[]; proposed quest accepted
           bp3 warden demoq --format json
           -> {"ok":true,"planned_gates":[{"quest":"demoq","node":"node-av-gate","kind":"human-gate","cycle":1,"reason":"AV signed off"}],"human_turns_count":4,"findings":[]}
           # unplanned e block on code node -> STILL Major human_steer

session.1  # PostToolUse hook appends durable quest-sessions/<q>.jsonl; Agy_tx/Claude_tx parse USER_INPUT + ask_question Q&A
           # bounded excerpts: agent_asked <= 300 chars, human_said <= 1000 chars, query step <= 2000 chars

session.2  # Standalone post-/red-ink audit AND quest-wide init..fin audit + drill-down query
           bp3 warden human-log --session latest --format json
           bp3 warden human-log demoq --phase red-ink --format json
           bp3 warden query latest --around 42 --window 5 --format table

skills.1   # /warden + using-bp3/induct/induct-yolo docs updated and verified
           make check-full -> all suites pass
```

## Goal and why

Fix two opposite blind spots in how Warden observes human involvement across a quest's life:
1. **Defect hygiene (Ticket #3):** Wire `--kind human-gate` (`v0.11.0`) into Warden so intentional owner checkpoints/decisions emit `0` `human_steer` findings and appear cleanly in `planned_gates[]`, while `e block` stays unambiguous for unplanned mid-node rescues (`Major human_steer`).
2. **Full-lifecycle learning (`init` -> `/red-ink` -> `induct` -> `fin` + standalone sessions):** Today Warden discards human message text and skips `/red-ink` and planning sessions. Giving OCaml a fast full-session interaction extractor (`human-log`) + step drill-down (`query`) lets `/warden` mine every human turn into `<= 3` concrete harness/skill proposals automatically — both right after `/red-ink` and at `quest fin`.

## Success picture

- `bp3 warden` reports `0` `human_steer` findings for `--kind human-gate` nodes and surfaces them in `planned_gates[]`, while keeping unplanned `e block`, cycle-cap escalations, and mid-code `USER_INPUT` as `Major human_steer`.
- `bp3 warden <quest>` works on proposed quests (`docs/quests/<q>/QUEST.md`) even before `bp3 q c <q>` has run.
- `hooks.ml` appends durable quest-session events to `.git/bp3/quest-sessions/<q>.jsonl` (surviving 24h statusline TTL), and `Warden_io` unions that log with a retroactive transcript-scan fallback.
- `bp3 warden human-log (<quest> | --session <id|latest>) [--phase ...]` extracts bounded `USER_INPUT` and paired `ask_question`/`AskUserQuestion` interactions across `agy` / `claude` / `pi`, tagged by phase (`init | red-ink | induct | fin | standalone`).
- `bp3 warden query <session-id|latest> --around <step> [--window 5]` returns bounded surrounding steps without loading raw multi-MB transcripts.
- `/warden` skill audits both standalone `/red-ink` sessions and full quests (`init..fin`), turning recurring human friction/preferences into `<= 3` proposals (never inflating `findings[]`).
- `make check-full` passes with unit, QCheck2, and CLI/fixture coverage.

## Scope

| In | Out |
|---|---|
| `ne_kind` in `Warden` / `Warden_io`, `human-gate` suppression of `human_steer`, `planned_gates[]` in JSON/table | Adding `--planned` flag on `e block` (explicitly killed in `/red-ink`: use `--kind human-gate` instead) |
| Proposed-quest acceptance in `bp3 warden <quest>` (`QUEST.md` fallback when `fold_quest = None`) | Adding LLM calls inside the `bp3 warden` OCaml binary (stays 100% deterministic) |
| Durable `.git/bp3/quest-sessions/<q>.jsonl` in `hooks.ml` + retroactive transcript-scan fallback | Indexing raw multi-MB transcripts into SQLite (direct OCaml JSONL scan stays zero-sync) |
| Full-session `HumanTurn` + `QueryStep` parsers (`agy_tx`, `claude_tx`, `pi_tx`) covering `USER_INPUT` + `ask_question` | Auto-applying `/warden` proposals without owner disposal |
| `bp3 warden human-log` and `bp3 warden query` subcommands + `--session <id\|latest>` + completions | Live daemon or real-time streaming monitor |
| Skill docs update (`warden`, `using-bp3`, `induct`, `induct-yolo`) as its own node | Retroactively patching `predictor`'s already-landed `ledger.jsonl` |

## Human touchpoints

- **Quest approval (before `induct`):** owner settles `/red-ink` and approves `QUEST.md` (`proposed -> active`).
- **Promotion (`bp3 release`):** owner runs `BP3_DECIDER=human bp3 release 2026-11-26-warden-planned-gates` after Warden audit & demo.

## Nodes

### Milestone: gate

### gate.1 - warden-human-gate-hygiene
Thread `ne_kind` into `Warden` / `Warden_io`, suppress Layer-1 & Layer-2 `human_steer` on `--kind human-gate` nodes, emit `planned_gates[]` in JSON and summary count in table, allow `bp3 warden <quest>` on proposed quests (`QUEST.md`), and cover with unit, QCheck2, and fixture tests. — [NODE.md](nodes/node-gate-1-warden-human-gate-hygiene/NODE.md)

### Milestone: session

### session.1 - quest-session-log-and-turn-parser
Add durable `.git/bp3/quest-sessions/<q>.jsonl` logging in `hooks.ml` plus pure full-session `HumanTurn` (`USER_INPUT` + paired `ask_question`/`AskUserQuestion`) and `QueryStep` window extractors in `Tx` / `Agy_tx` / `Claude_tx` / `Pi_tx`, with unit & QCheck2 bounds tests. — [NODE.md](nodes/node-session-1-quest-session-log-and-turn-parser/NODE.md)

### session.2 - warden-human-log-and-query-cli
Reserve and implement `bp3 warden human-log` (`<quest>` unioning hook log + retroactive scan, or `--session <id|latest>`, `--phase`, `--limit`) and `bp3 warden query <session-id|latest> --around <step> [--window 5]`, add `human_turns_count` to default `bp3 warden` JSON, update completions & help, and cover with unit + CLI fixture tests. — [NODE.md](nodes/node-session-2-warden-human-log-and-query-cli/NODE.md)

### Milestone: skills

### skills.1 - document-human-gate-and-full-session-warden
Document `--kind human-gate` vs unplanned `e block`, `planned_gates[]`, `bp3 warden human-log`, `bp3 warden query`, and standalone `/red-ink` + full-lifecycle `init..fin` `/warden` passes across `skills/{warden,using-bp3,induct,induct-yolo}/SKILL.md` (plus repo-local `using-bp3` renders) and guard in `test/skills.sh`. — [NODE.md](nodes/node-skills-1-document-human-gate-and-full-session-warden/NODE.md)

## Scorecard

| Metric | Target |
|---|---|
| False-positive `human_steer` on `--kind human-gate` nodes | `0` |
| True-positive `human_steer` on unplanned `e block`, cycle-cap escalation, or mid-code steer | `100%` detected |
| Standalone post-`/red-ink` & quest-wide `init..fin` human turns extracted (incl. `ask_question`) | `100%` captured, bounded (`<= 1000` chars/turn) |
| `make check-full` | `100%` green |

## Risks and red chair

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Pure OCaml (`stdlib`, `unix`, `yojson`, `ounit2`, `qcheck-core`) + Bash/Zsh completions + Markdown skills. `bp3 warden` is already an allowed CLI surface; `human-log` and `query` are subcommands under it. Zero new languages, libraries, or surfaces.
- **Common-sense pass (`CONTEXT.md`):** Aligns with `Q1` (deterministic OCaml extracts exact facts/slices; LLM `/warden` does pattern judgment — "the two never mix") and `Q2` (transcripts stay flat JSONL files, no daemon or secondary DB sync).
- **Closing red chair (settled during `/red-ink`):**
  1. *Flag bloat & gaming risk (eliminated):* Initial draft added `--planned` on `e block`; `/red-ink` killed it completely in favor of existing `--kind human-gate` (`v0.11.0`), eliminating flag bloat, self-attestation loopholes, and wake-up timing heuristics.
  2. *Standalone `--session <id|latest>` plug scope (Major — settled in `session.2`):* When `bp3 warden --session <id|latest>` runs without a quest ledger, `scope = "session"`, `quests = []`, `planned_gates = []`, Layer-1 git/ledger plugs are skipped, and Layer-2 runs only `tool_retry_loop` + `context_bloat` (never `human_steer` or `full_gate_in_author` on standalone `/red-ink` / ad-hoc sessions).
  3. *Retroactive scan performance on large `~/.gemini/antigravity-cli/brain` dirs (Major — settled in `session.2`):* Default `bp3 warden [<quest>]` computes `human_turns_count` ONLY from `.git/bp3/quest-sessions/<q>.jsonl` + already-joined traces (O(1) lookup, never scanning all transcripts). Retroactive full-dir scan runs ONLY on `bp3 warden human-log <quest>`, using a fast `Tx.contains` pre-filter before JSON parsing.
  4. *`agy` `transcript_full.jsonl` truncation & `human-gate` pending state (Minor — settled in `session.1` & `gate.1`):* `Agy_tx` reuses its existing `truncated_fields` resolver so long `USER_INPUT` / `ask_question` replies aren't lost; `planned_gates[]` lists approved `human-gate` nodes (with `approved_reason`) while unapproved `human-gate` nodes also emit `0` `human_steer`.
  5. *`--session latest` concurrency ambiguity (Minor — accepted):* `--session latest` always prints the resolved `session_id` in output; explicit `--session <id>` is always available when multiple terminals are open.

## Open questions

None blocking `induct`.

## Node diagram

```text
Cohort 1 (parallel):  [ gate.1 - warden-human-gate-hygiene ]   [ session.1 - quest-session-log-and-turn-parser ]
                                         \                                 /
                                          v                               v
Cohort 2:                              [ session.2 - warden-human-log-and-query-cli ]
                                                          |
                                                          v
Cohort 3:                           [ skills.1 - document-human-gate-and-full-session-warden ]
```
