---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# warden-v0: two-layer deterministic plugs (git + auto-enabled session traces) + /warden loop

TL;DR
Unfreeze Warden without waiting for SQLite or a Chrome-trace profiler. `bp3 q <quest> warden` runs **9 composable, pure OCaml plug rules** across two layers: **Layer 1 (git-only, 6 plugs)** over `ledger.jsonl`, `metrics.jsonl`, and `Worktree` desk state, plus **Layer 2 (session-trace, 3 plugs, auto-enabled)** directly over the Claude, Pi, and `agy` session transcripts that `Tx` / `Metrics_io` already locates on disk (citing exact `transcript.jsonl` step/line refs, degrading gracefully when local transcripts are pruned, or skippable via `--no-sessions`). A new `/warden` skill (wired into `/trial` at `goal_fin`) reads those findings and proposes at most 3 concrete harness patches (lint/script, `GRADING.md`/brief, skill rule, or rule pruning); the owner disposes.

ELI5
Warden stayed frozen because it waited on a big SQLite + profiler chain, even though `bp3` already stores every grade bounce, wall-clock duration, token spend, and refusal in git AND already parses every Claude/Pi/`agy` session transcript in `metrics scrape`. Now `bp3 q <quest> warden` scores both layers automatically — catching slow cycles, minor-only bounces, vacuous tests, tool retry loops, mid-cycle `make check-full` spam, and context bloat — and `/warden` turns recurring waste into 1-3 tiny patches every time a quest finishes.

## Context

Draws from `docs/icebox/2026-11-17-warden-plug-rules.md` (copied verbatim to [ICEBOX.md](ICEBOX.md)) and `docs/icebox/2026-11-17-mini-warden-run-budgets.md`. Rather than waiting on the heavy SQLite + Chrome-trace miner chain (`2026-11-17-tape-scraper-sqlite.md` -> `2026-11-17-run-profiler-chrome-trace.md`), `warden-v0` ships the deterministic plug architecture right now over existing `bp3` data; the SQLite/profiler icebox entries remain frozen for deep raw-tape mining if ever needed later.

Measured ground (read 2026-11-23):

| Fact | Source |
|---|---|
| `CONTEXT.md:58`: `"Every mistake becomes a permanent fix: an instruction line, a lint rule or a test. bp3: runs/*/notes.md, with no path from a note to a rule yet."` | `CONTEXT.md:58` |
| `CONTEXT.md:59, 62`: rules need pruning too (`"a 10 kB CLAUDE.md isn't learning, it's costuming"`); what must hold goes in a lint/script, not prose | `CONTEXT.md:59, 62` |
| `metrics.jsonl` + node `ledger.jsonl` ALREADY contain cycles, `grade.wall_s`, `author.wall_s`, `grade.tokens_out`, `author.tokens_out`, `needs_fix` reasons, `brief_edited`, `author_missing`, `owner_graded`, and refused `E_*` rows | `src/quest/metrics.ml`, `src/quest/metrics_io.ml`, `src/quest/store.ml` |
| Running our 6 rules manually against `2026-11-22-induct-inline-as-default-measure-author` caught 4 `minor_only_bounce` rounds, 4 `vacuous_test_bounce` rounds, 4/5 `grade_inversion` nodes, and 4 `cycle_outlier` nodes — with zero SQLite | manual audit (2026-11-23) |
| Pending input: `docs/learn/get-good-harness-engineering.md` (Grok report, in progress) will be folded in before approval | owner (2026-11-23) |

## Terms

| Term | Meaning |
|---|---|
| plug | a pure OCaml function `Warden.evidence -> Warden.finding list` in `src/quest/warden.ml`; independent, deterministic, never mutates state |
| Layer 1 (git-only) | 6 deterministic plugs reading `ledger.jsonl`, `metrics.jsonl`, and open desks (`cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`, `coverage_gap`, `desk_leak`); always runs, even if local transcripts were pruned |
| Layer 2 (session-trace) | 3 deterministic plugs reading joined `Tx` session traces (`tool_retry_loop`, `full_gate_in_author`, `context_bloat`); **auto-enabled** whenever local transcripts match on disk, citing exact `transcript.jsonl#L<n>` / `step:<n>` refs; disabled with `--no-sessions` |
| finding | typed record `{ rule; layer; severity; quest; node; cycle; evidence_ref; summary }` emitted by `bp3 q <quest> warden` |
| `warden` | CLI verb `bp3 q <quest> warden [--no-sessions] [--format json\|table]` and `bp3 q warden --all-landed [--no-sessions] [--format json\|table]` (reserved in `Store.reserved_slugs` + `Names.verb_warden`) |
| `/warden` | new core skill (`skills/warden/SKILL.md`): runs `bp3 q <quest> warden`, inspects cited evidence, and proposes <=3 concrete harness patches (or rule prunes) for owner approval |
| false-positive budget | backtest bar (`dogfood.1`): <= 20% junk findings across the last 4 landed quests; rules exceeding it get tightened or dropped |

## Inputs

| Input | Source |
|---|---|
| quest & node ledgers | `refs/heads/bp3/node/<quest>/<node>:.../ledger.jsonl` via `Store.fold_node` |
| node metrics | `refs/heads/bp3/node/<quest>/<node>:.../metrics.jsonl` via `Metrics_io.read_samples` |
| desk list | `Worktree.list` (for unreleased grade desks) |
| local session transcripts (Layer 2, auto-enabled) | `~/.claude/projects/`, `~/.pi/agent/sessions/`, `~/.gemini/antigravity-cli/brain/` via `Metrics_io.joined_traces` (from `2026-11-23-fast-agy-induct` `agy.1`; overrideable via `--dir`/`--pi-dir`/`--agy-dir` in tests) |
| CLI flags | `[--all-landed]`, `[--no-sessions]` (force Layer 1 only), `[--format json\|table]` (default `json`) |

## Outputs

| Output | Shape |
|---|---|
| `bp3 q <quest> warden` (JSON) | `{"ok":true,"quests":[...],"sessions_scanned":N,"findings":[{"rule","layer","severity","quest","node","cycle","evidence_ref","summary"}],"counts":{"by_rule":{...},"by_layer":{"git":M,"session":K},"total":T}}`; always exit 0 on clean read (findings are evidence, never a gate) |
| `bp3 q <quest> warden --format table` | compact human-readable table on stdout (`rule \| layer \| sev \| node \| cycle \| summary`) |
| `/warden` skill report | deterministic findings table + <=3 concrete patch proposals (exact file/change or rule to prune); owner disposes |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden
{"ok":false,"error":{"code":"E_USAGE",...}}
$ ls skills/warden/SKILL.md
ls: skills/warden/SKILL.md: No such file or directory
```

Design trace (after quest lands):

```text
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden
  - ok: true, rc 0, sessions_scanned >= 0 (auto-enabled Layer 2 when local transcripts exist)
  - Layer-1 findings include:
      cycle_outlier       (brief.2 c4, skills.2 c4, brief.1 c3, skills.1 c3)
      minor_only_bounce   (measure.1 c1, brief.2 c2, brief.2 c3, skills.1 c2)
      vacuous_test_bounce (measure.1 c1, brief.1 c1, brief.1 c2, skills.2 c3)
      grade_inversion     (measure.1, brief.2, skills.1, skills.2)
  - Layer-2 findings (when local transcripts match): tool_retry_loop, full_gate_in_author, context_bloat citing transcript step/line refs
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden --no-sessions
  - Layer 1 only (< 1s), sessions_scanned: 0, rc 0
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden --format table
  - prints human table cleanly, rc 0
$ ./bin/bp3 q warden --all-landed
  - sweeps every landed quest in refs/heads/bp3/quest/*
$ ./bin/bp3 q warden -h
  - prints docstring + flags on stdout, rc 0, reads no state
```

## Goal and why

Close the self-improving loop in `bp3`. Today, friction and waste stay buried in `metrics.jsonl`, `runs/*/notes.md`, and local transcripts until the owner complains ("this takes half a day"). A tiny two-layer deterministic plug pipeline over existing `bp3` git state + `Tx` session traces catches recurring waste automatically at `goal_fin`, and `/warden` turns recurring patterns into concrete lint/script/brief patches (or prunes stale rules) with human sign-off.

## Success picture

- `src/quest/warden.ml` implements 9 pure, deterministic plugs (6 Layer-1 git + 3 Layer-2 session-trace) with unit tests and reproduces every finding from our `2026-11-22` manual audit.
- `bp3 q <quest> warden` auto-enables Layer 2 when local Claude/Pi/`agy` transcripts exist (`--no-sessions` runs Layer 1 in `<1s`), with zero SQLite, zero daemon, and zero LLM in the plug layer.
- `/warden` skill lives in `CORE_SKILLS` and is wired into `/trial` at `goal_fin` with a hard anti-bloat cap (<=3 proposals per run; prefer lint/script over prose; prune stale rules).
- Backtest across the last 4 landed quests (`dogfood.1`) hits <= 20% false positives across both layers.

## Scope

| In | Out |
|---|---|
| `src/quest/warden.ml` (6 Layer-1 git plugs + 3 Layer-2 `Tx` session-trace plugs), `bp3 q <quest> warden` CLI door (Layer 2 auto-enabled, `--no-sessions`), `Names.verb_warden`, unit + fixture tests | SQLite tape database (`2026-11-17-tape-scraper-sqlite.md`, stays frozen) |
| `skills/warden/SKILL.md` (in `CORE_SKILLS`), wiring into `skills/trial/SKILL.md` (+ renders) | Chrome-trace profiler (`2026-11-17-run-profiler-chrome-trace.md`, stays frozen) |
| Backtesting and threshold tuning across last 4 landed quests (`dogfood.1`) | Mid-run intervention, auto-blocking, or auto-committing patches without owner approval |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** OCaml (`stdlib`, `str`, `yojson`, `ounit2`) + Bash fixture test + Markdown skill. Zero new languages, libraries, or surfaces (`warden` rides the signed `bp3 q` door).
- **Common-sense pass (`CONTEXT.md`):**
  - Every mistake becomes a permanent fix (`CONTEXT.md:58`): `/warden` creates the missing path from evidence -> lint/script/rule.
  - Rules need pruning too (`CONTEXT.md:59, 62`): `/warden` explicitly checks for dead/bloated prose rules to delete, not only add.
  - Deterministic scripts separate from LLM judgment (`CONTEXT.md:23`, `ICEBOX.md:55`): `bp3 q warden` mints all findings deterministically; the LLM in `/warden` only summarizes and drafts candidate patches.

## Human touchpoints

| When | Owner |
|---|---|
| Approve frame (after Grok report fold-in) | owner |
| Dispose `/warden` patch proposals at each `goal_fin` | owner |
| Promotion (`goal_fin`) | owner |

## Nodes

### Milestone: plugs

| Node | TL;DR |
|---|---|
| [plugs.1 - warden-engine](nodes/node-plugs-1-warden-engine/NODE.md) | pure OCaml plug pipeline `src/quest/warden.ml` with 9 deterministic rules (6 Layer-1 git + 3 Layer-2 session-trace) + `test/unit/test_warden.ml` |

### Milestone: cli

| Node | TL;DR |
|---|---|
| [cli.1 - warden-door](nodes/node-cli-1-warden-door/NODE.md) | `bp3 q <quest> warden [--all-landed] [--no-sessions] [--format json\|table]` auto-loading Layer-2 `Tx` traces via `Metrics_io` + `test/warden.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - warden-skill-and-trial-hook](nodes/node-skills-1-warden-skill-and-trial-hook/NODE.md) | add `skills/warden/SKILL.md` (`CORE_SKILLS`) and wire into `skills/trial/SKILL.md` (+ all renders, skill node) |

### Milestone: dogfood

| Node | TL;DR |
|---|---|
| [dogfood.1 - backtest-recent-quests](nodes/node-dogfood-1-backtest-recent-quests/NODE.md) | run `bp3 q warden --all-landed` over the last 4 landed quests, audit precision/false positives (<=20%), tune thresholds |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| `2026-11-22` recall | reproduces all 4 waste classes (`cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`) | `bp3 q 2026-11-22-... warden` |
| execution latency | < 1s per quest | timed run |
| false-positive rate | <= 20% across last 4 landed quests | `dogfood.1` audit table in `QUEST.md` |
| anti-bloat cap | <= 3 patch proposals per `/warden` run | `skills/warden/SKILL.md` + `test/skills.sh` |

## Risks and red chair

- **Strongest attack (prompt/rule bloat — "costuming", `CONTEXT.md:62`):** "A self-improving loop that appends a rule to `GRADING.md` or `AGENTS.md` after every quest turns into a 10 KB prompt monster within a month."
  - **Settled in design:** `skills.1` imposes three hard brakes: (1) prefer deterministic lint/script/test fixes over prose rules, (2) cap `/warden` at <= 3 proposals per quest, and (3) require a pruning check — if `GRADING.md` / `AGENTS.md` / a skill grows, name a stale line to delete or justify why not; owner approves every patch.
- **Second attack (noisy thresholds -> alert fatigue):** "Fixed thresholds like `grade_wall_s > 300s` or `cycles > 2` could spam false positives on genuinely hard quests."
  - **Settled in design (`dogfood.1`):** thresholds are backtested against the last 4 real landed quests and tuned before promotion so false-positive rate stays <= 20%; thresholds are read from `Config.thresholds` (or clean constants in `warden.ml` tunable per machine).
- **Attack on source (`ICEBOX.md`):**
  - *Icebox assumption rejected:* `docs/icebox/2026-11-17-warden-plug-rules.md` claimed "no warden before SQLite DB exists." Rejected with live evidence: 6 git-level plugs run directly on `ledger.jsonl` + `metrics.jsonl` in <1s, and 3 session-trace plugs piggyback directly on `Metrics_io.joined_traces` (already parsing Claude/Pi/`agy` transcripts with zero SQLite!). Only raw-tape rules specific to the retired Muse JS workflows (#1 output-byte copying, #3 dropped dispatch arg) stay deferred.
  - *Minor-only regex fragility (major concern):* parsing `[minor]`/`[major]`/`[critical]` out of free-text `grade --reason` strings could miss verdicts that don't tag severity brackets. **Settled in `plugs.1`:** `minor_only_bounce` fires ONLY when the reason explicitly carries `[minor]` AND zero `[critical]`/`[major]` (conservative precision-first: zero false positives on untagged historical reasons, exact match on `Brief.render` verdict shape).
  - *Missing local transcripts (major concern):* local `~/.claude` / `~/.pi` / `~/.gemini/antigravity-cli/brain` files can be pruned or absent on another machine. **Settled in `plugs.1` + `cli.1`:** Layer 2 auto-enables when local transcripts match and degrades cleanly to `sessions_scanned: 0` (never errors); `tool_errors` and `turns` are also persisted to `metrics.jsonl` by `agy.1` so high-level error/turn signals survive in git forever.

## Open questions

1. Fold in any self-improvement / trace-mining patterns from `docs/learn/get-good-harness-engineering.md` (Grok report) before approval — **owner + agent**.
2. Keep `docs/icebox/2026-11-17-warden-plug-rules.md` frozen for future raw-tape plugs, or mark it promoted and delete it at approval (since `ICEBOX.md` preserves it verbatim)? — **owner**.
3. Run `/warden` automatically at `/trial` only, or also add a weekly `/schedule` sweep on `agy`? — **owner**.

## Node diagram

```text
(uses Tx + Metrics_io.joined_traces from 2026-11-23-fast-agy-induct agy.1)

plugs.1 (warden.ml: 6 git + 3 session plugs) ──► cli.1 (bp3 q warden, Layer 2 auto) ──► skills.1 (/warden + /trial hook) ──► dogfood.1 (4-quest backtest)
```
