---
status: active
home_repo: bp3
date: 2026-11-23
bump: minor
---

# warden-v0: two-layer deterministic plugs (git + auto-enabled session traces) + /warden loop

TL;DR
Unfreeze Warden without waiting for SQLite or a Chrome-trace profiler. Top-level **`bp3 warden [<quest>]`** runs **12 composable, pure OCaml plug rules** across two layers: **Layer 1 (git-only, 8 plugs)** over `ledger.jsonl`, `metrics.jsonl`, `Worktree` desks, post-land fix commits, and repo-level invariants (like `>1 active quest`), plus **Layer 2 (session-trace, 4 plugs, auto-enabled)** directly over the Claude, Pi, and `agy` session transcripts that `Tx` / `Metrics_io` already locates on disk (including mid-build `human_steer`, citing exact `transcript.jsonl` step/line refs, degrading gracefully when local transcripts are pruned, or skippable via `--no-sessions`). With `<quest>`, it audits that quest; with no args, it runs repo checks + `--last 5` unreviewed real quests (skipping quests that already have `FEEDBACK.md`). `/trial` is renamed and merged into a single **`/warden`** skill that wraps quest landing + self-improvement: runs the diligence gate & Landing IIUC/trial, runs `bp3 warden <quest>`, writes the standalone **`FEEDBACK.md`** (human feedback + Warden summary + <=3 proposals + owner disposition), and disposes approved fixes (small 1–2 file fixes applied directly as a clean commit on owner go; larger changes frozen to `docs/icebox/` or framed as a follow-up quest).

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
| Layer 1 (git-only) | 8 deterministic plugs reading `ledger.jsonl`, `metrics.jsonl`, `QUEST.md` statuses, git history after final `node_fin`, and open desks (`multi_active_quest`, `cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion` [floor `>180s` & `>1.5x` author wall], `coverage_gap`, `desk_leak`, `post_land_bugfix` [non-status commits after final `node_fin`]); always runs, even if local transcripts were pruned |
| Layer 2 (session-trace) | 4 deterministic plugs reading joined `Tx` session traces (`tool_retry_loop`, `full_gate_in_author`, harness-aware `context_bloat` [`>150k` Claude/Pi, `>400k` `agy`, or `turns > 30`], `human_steer` [mid-node `USER_INPUT` inside `[prev_edge_ts .. handoff_ts]` author windows excluding the opening kickoff prompt, plus Layer-1 `block` edges]); **auto-enabled** whenever local transcripts match on disk, citing exact `transcript.jsonl#L<n>` / `step:<n>` refs; disabled with `--no-sessions` |
| finding | typed record `{ rule; layer; severity; quest; node; cycle; observed; threshold; evidence_ref; summary }` emitted by `bp3 warden` |
| `warden` | top-level CLI door `bp3 warden [<quest>] [--last N\|--all] [--no-sessions] [--format json\|table]` and `bp3 warden -h` (dispatched from `bin/bp3` into `main.exe warden ...`; no `<quest>` runs repo-level checks + last 5 unreviewed real quests without `FEEDBACK.md`) |
| `FEEDBACK.md` | standalone authored post-quest feedback & Warden audit file (`docs/quests/<quest>/FEEDBACK.md`, `Layout.feedback_file`): holds human post-land notes, Warden summary, <=3 proposals, and owner disposition; its presence marks a quest as reviewed for bare `bp3 warden` |
| `/warden` | unified core skill (`skills/warden/SKILL.md`, replacing/renaming `skills/trial/SKILL.md`): wraps quest landing (diligence gate, Landing IIUC + runnable trial) with `bp3 warden <quest>`, writes `FEEDBACK.md`, and proposes <=3 concrete harness fixes (small 1–2 file fixes applied as a clean commit on owner go; big multi-file fixes frozen to `docs/icebox/` or framed as a follow-up quest) |
| false-positive budget | backtest bar (`dogfood.1`): <= 20% junk findings across the last 4 landed quests; rules exceeding it get tightened or dropped |

## Inputs

| Input | Source |
|---|---|
| quest & node ledgers | `refs/heads/bp3/node/<quest>/<node>:.../ledger.jsonl` via `Store.fold_node` |
| node metrics | `refs/heads/bp3/node/<quest>/<node>:.../metrics.jsonl` via `Metrics_io.read_samples` |
| desk list | `Worktree.list` (for unreleased grade desks) |
| local session transcripts (Layer 2, auto-enabled) | `~/.claude/projects/`, `~/.pi/agent/sessions/`, `~/.gemini/antigravity-cli/brain/` via `Metrics_io.joined_traces` (from `2026-11-23-fast-agy-induct` `agy.1`; overrideable via `--dir`/`--pi-dir`/`--agy-dir` in tests) |
| CLI flags | `[<quest>]` (omit for repo-wide sweep: repo checks + `--last 5` real quests with `QUEST.md`), `[--last N]` (default `5`), `[--all]` (sweep all real quests), `[--no-sessions]` (force Layer 1 only), `[--format json\|table]` (default `json`), `[--dir\|--pi-dir\|--agy-dir]` (test transcript overrides) |

## Outputs

| Output | Shape |
|---|---|
| `bp3 warden [<quest>]` (JSON) | `{"ok":true,"scope":"quest\|repo","quests":[...],"sessions_scanned":N,"findings":[{"rule","layer","severity","quest","node","cycle","observed","threshold","evidence_ref","summary"}],"counts":{"by_rule":{...},"by_layer":{"git":M,"session":K},"total":T}}`; always exit 0 on clean read (findings are evidence, never a gate); exit 2 on `E_USAGE` / `E_NOT_FOUND` |
| `bp3 warden [<quest>] --format table` | compact human-readable table on stdout (`rule \| layer \| sev \| node \| cycle \| observed \| summary`) |
| `/warden` skill report | deterministic findings table + standalone `FEEDBACK.md` + <=3 concrete patch proposals (exact file/change or rule to prune); owner disposes |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author
usage: bp3 init ... (unknown door: warden)
$ ls skills/warden/SKILL.md
ls: skills/warden/SKILL.md: No such file or directory
```

Design trace (after quest lands):

```text
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author
  - ok: true, scope: "quest", rc 0, sessions_scanned >= 0 (auto-enabled Layer 2 when local transcripts exist)
  - every finding carries structured observed + threshold fields alongside summary
  - Layer-1 findings include:
      cycle_outlier       (brief.2 c4, skills.2 c4, brief.1 c3, skills.1 c3)
      minor_only_bounce   (measure.1 c1, brief.2 c2, brief.2 c3, skills.1 c2)
      vacuous_test_bounce (measure.1 c1, brief.1 c1, brief.1 c2, skills.2 c3)
      grade_inversion     (measure.1, brief.2, skills.1, skills.2)
  - Layer-2 findings (when local transcripts match): tool_retry_loop, full_gate_in_author, context_bloat citing transcript step/line refs
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author --no-sessions
  - Layer 1 only (< 1s), sessions_scanned: 0, rc 0
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author --format table
  - prints human table cleanly, rc 0
$ ./bin/bp3 warden
  - scope: "repo", runs repo-level checks (>1 active quest, leaked desks) + last 5 real quests (with docs/quests/<q>/QUEST.md), rc 0
$ ./bin/bp3 warden --all
  - scope: "repo", sweeps every real quest in docs/quests/*/QUEST.md, rc 0
$ ./bin/bp3 warden -h
  - prints docstring + flags on stdout, rc 0, reads no state
```

## Goal and why

Close the self-improving loop in `bp3`. Today, friction and waste stay buried in `metrics.jsonl`, `runs/*/notes.md`, and local transcripts until the owner complains ("this takes half a day"). A tiny two-layer deterministic plug pipeline over existing `bp3` git state + `Tx` session traces catches recurring waste automatically at `goal_fin`, and `/warden` turns recurring patterns into concrete lint/script/brief patches (or prunes stale rules) with human sign-off.

## Success picture

- `src/warden/warden.ml` (`bp3_warden` dune library) implements 12 pure, deterministic plugs (8 Layer-1 git/repo + 4 Layer-2 session-trace, including `multi_active_quest`, `post_land_bugfix`, and `human_steer`) with unit tests and reproduces every finding from our `2026-11-22` manual audit.
- Top-level `bp3 warden [<quest>] [--last N|--all] [--no-sessions] [--format json|table]` (`src/warden/warden_io.ml` + `bin/bp3` -> `main.exe warden`) auto-enables Layer 2 when local Claude/Pi/`agy` transcripts exist (`--no-sessions` runs Layer 1 in `<1s`), skips quests that already have `FEEDBACK.md` on bare `bp3 warden`, and stays 100% read-only with zero SQLite, zero daemon, and zero LLM in the plug layer.
- Unified `/warden` skill (`skills/warden/SKILL.md`, replacing/removing `skills/trial/SKILL.md` in `CORE_SKILLS`) wraps quest landing + self-improvement, writes standalone `docs/quests/<quest>/FEEDBACK.md`, enforces the anti-bloat cap (<=3 proposals; prefer lint/script over prose; prune stale rules), and uses tiered owner disposal.
- Backtest across the last 4 landed quests (including `2026-11-23-fast-agy-induct`) in `dogfood.1` hits <= 20% false positives across both layers, recorded in `LOG.md` / `FEEDBACK.md`.

## Scope

| In | Out |
|---|---|
| `src/warden/dune` (`bp3_warden`), `src/warden/warden.ml` (8 Layer-1 git/repo + 4 Layer-2 `Tx` session-trace plugs), `src/warden/warden_io.ml` (read-only I/O edge), `Tx`/`Agy_tx`/`Claude_tx`/`Pi_tx` `s_user_steps`, top-level `bp3 warden` CLI door (`bin/bp3` + `main.exe`), `Layout.feedback_file` (`FEEDBACK.md`), unit + fixture tests | SQLite tape database (`2026-11-17-tape-scraper-sqlite.md`, stays frozen) |
| `skills/warden/SKILL.md` (renaming/replacing `skills/trial/SKILL.md` in `CORE_SKILLS` + all renders + stale `trial` cleanup + `FEEDBACK.md` output + tiered disposal) | Chrome-trace profiler (`2026-11-17-run-profiler-chrome-trace.md`, stays frozen) |
| Backtesting and threshold tuning across last 4 landed quests (`dogfood.1`) | Mid-run intervention, auto-blocking, or auto-committing patches without owner approval |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** OCaml (`stdlib`, `str`, `yojson`, `ounit2`, `qcheck-core`, `qcheck-ounit`) + Bash fixture test + Markdown skill. Zero new languages or external libraries (`bp3_warden` in `src/warden/dune` is an internal library recognized by `scripts/check-constraints`). `cli.1` adds `bp3 warden` to `CONSTRAINTS.md:49` (`bp3 CLI` surface) with a dated owner-words Sign-off log row (owner, 2026-11-23: `"Should Warden be its own top-level command — bp3 warden ... lock"`).
- **Common-sense pass (`CONTEXT.md`):**
  - Every mistake becomes a permanent fix (`CONTEXT.md:58`): `/warden` creates the missing path from evidence -> lint/script/rule.
  - Rules need pruning too (`CONTEXT.md:59, 62`): `/warden` explicitly checks for dead/bloated prose rules to delete, not only add.
  - Deterministic scripts separate from LLM judgment (`CONTEXT.md:23`, `ICEBOX.md:55`): `bp3 warden` mints all findings deterministically; the LLM in `/warden` only summarizes, writes `FEEDBACK.md`, and drafts candidate patches.

## Human touchpoints

| When | Owner |
|---|---|
| Settle red-ink & approve quest | owner |
| Dispose `/warden` proposals at quest landing (`goal_fin`) | owner |
| Promotion (`goal_fin`) | owner |

## Nodes

### Milestone: plugs

| Node | TL;DR |
|---|---|
| [plugs.1 - warden-engine](nodes/node-plugs-1-warden-engine/NODE.md) | `src/warden/dune` (`bp3_warden`) + `src/warden/warden.ml` with 12 pure plugs (8 Layer-1 incl. `multi_active_quest` & `post_land_bugfix` + 4 Layer-2 incl. `human_steer`, calibrated `context_bloat` & `grade_inversion`, structured `observed`/`threshold`) + `s_user_steps` in `Tx`/`Agy_tx`/`Claude_tx`/`Pi_tx` + `test/unit/test_warden.ml` |

### Milestone: cli

| Node | TL;DR |
|---|---|
| [cli.1 - warden-door](nodes/node-cli-1-warden-door/NODE.md) | `src/warden/warden_io.ml` + top-level `bp3 warden [<quest>] [--last N\|--all] [--no-sessions] [--format json\|table]` (`bin/bp3` + `main.exe`), `Layout.feedback_file` (`FEEDBACK.md` skip on bare `bp3 warden`), auto-loading Layer-2 `Tx` traces via `Metrics_io` + `test/warden.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - warden-skill](nodes/node-skills-1-warden-skill-and-trial-hook/NODE.md) | rename/replace `skills/trial/SKILL.md` (currently in `DEV_SKILLS`) with unified `skills/warden/SKILL.md` in `CORE_SKILLS`, remove `trial` from `DEV_SKILLS`, update `skills/quest/SKILL.md` & `skills/induct/SKILL.md` refs, re-render all harnesses + clean stale `trial` dirs + `test/skills.sh` + `test/mode.sh` |

### Milestone: dogfood

| Node | TL;DR |
|---|---|
| [dogfood.1 - backtest-recent-quests](nodes/node-dogfood-1-backtest-recent-quests/NODE.md) | run `bp3 warden` across the last 4 landed quests (including `2026-11-23-fast-agy-induct`), audit precision/false positives (<=20%), tune thresholds, record audit table in `LOG.md` + `FEEDBACK.md` |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| `2026-11-22` recall | reproduces all 4 waste classes (`cycle_outlier`, `minor_only_bounce`, `vacuous_test_bounce`, `grade_inversion`) | `bp3 warden 2026-11-22-...` |
| execution latency | < 1s per quest (`--no-sessions`) | timed run |
| false-positive rate | <= 20% across last 4 landed quests | `dogfood.1` audit table in `LOG.md` |
| anti-bloat cap | <= 3 patch proposals per `/warden` run | `skills/warden/SKILL.md` + `test/skills.sh` |

## Risks and red chair

- **Strongest attack (prompt/rule bloat — "costuming", `CONTEXT.md:62`):** "A self-improving loop that appends a rule to `GRADING.md` or `AGENTS.md` after every quest turns into a 10 KB prompt monster within a month."
  - **Settled in design:** `skills.1` imposes three hard brakes: (1) prefer deterministic lint/script/test fixes over prose rules, (2) cap `/warden` at <= 3 proposals per quest, and (3) require a pruning check — if `GRADING.md` / `AGENTS.md` / a skill grows, name a stale line to delete or justify why not; owner approves every patch.
- **Second attack (noisy thresholds -> alert fatigue):** "Fixed thresholds like `grade_wall_s > 300s` or `context_end > 150k` spam false positives on `agy` 1M-window runs or quick 2m grades."
  - **Settled in design:** `context_bloat` is harness-aware (`>150k` Claude/Pi, `>400k` `agy`, or `turns > 30`), `grade_inversion` uses a `>180s` & `>1.5x` floor, and `dogfood.1` backtests all 12 plugs across 4 real landed quests (<=20% FP bar).
- **Attack on source (`ICEBOX.md`):**
  - *Icebox assumption rejected:* `docs/icebox/2026-11-17-warden-plug-rules.md` claimed "no warden before SQLite DB exists." Rejected with live evidence: 8 git/repo plugs run directly on `ledger.jsonl`, `metrics.jsonl`, `QUEST.md`, and git history in `<1s`, and 4 session-trace plugs piggyback directly on `Metrics_io.joined_traces` (already parsing Claude/Pi/`agy` transcripts with zero SQLite!).
  - *Minor-only regex fragility (major concern):* settled by requiring explicit `[minor]` AND zero `[critical]`/`[major]`.
  - *Missing local transcripts (major concern):* Layer 2 auto-enables when local transcripts match and degrades cleanly to `sessions_scanned: 0` (never errors).

## Open questions

1. Fold any extra patterns from `docs/learn/get-good-harness-engineering.md` / `docs/dossiers/2026-11-23-harness-advice.md` into `warden-v0` or defer to `v1`? — **owner**.
2. Keep `/warden` manual/at-landing only, or also add a weekly `/schedule` sweep on `agy`? — **owner**.

## Node diagram

```text
(uses Tx + Metrics_io.joined_traces from 2026-11-23-fast-agy-induct)

plugs.1 (src/warden/warden.ml: 8 git + 4 session plugs + s_user_steps)
   ──► cli.1 (src/warden/warden_io.ml + top-level bp3 warden + FEEDBACK.md skip)
   ──► skills.1 (unified /warden replacing /trial + FEEDBACK.md + tiered disposal)
   ──► dogfood.1 (4-quest backtest <= 20% FP)
```

## Quest-level functional tests

1. **Happy path — full two-layer quest audit (functional fixture in `test/warden.sh`):**
   - *Start:* Temp git repo with a landed quest holding planted Layer-1 issues (3 cycles, minor-only bounce, vacuous-test bounce, leaked grade desk, 2 post-land fix commits, 2 active quests) and fake Claude/`agy` transcripts (`--dir`, `--agy-dir`) holding 3x tool retry loop, 2x `make check-full`, `>400k` `agy` context_end, and 2 mid-build `USER_INPUT` turns.
   - *Action:* `./bin/bp3 warden <quest>` and `./bin/bp3 warden <quest> --format table`.
   - *Result:* Exit `0`; JSON has `ok: true`, `scope: "quest"`, `sessions_scanned > 0`, all 12 rules fire with non-empty `observed`, `threshold`, `evidence_ref`; table prints cleanly; `git status` and git refs are unchanged (read-only).
2. **Reviewed-quest skip & override (`FEEDBACK.md`, functional fixture):**
   - *Start:* Temp repo with 2 real quests; quest A has `FEEDBACK.md`, quest B does not.
   - *Action:* Bare `./bin/bp3 warden`, then `./bin/bp3 warden --all`, then `./bin/bp3 warden <quest-A>`.
   - *Result:* Bare call audits only quest B (+ repo checks); `--all` and explicit `<quest-A>` audit quest A too.
3. **Refusal & degradation paths (functional fixture):**
   - *Start:* Empty transcript dirs (`--dir <empty> --agy-dir <empty>`) and invalid CLI calls.
   - *Action:* `./bin/bp3 warden <quest> --no-sessions`, `./bin/bp3 warden unknown-q`, `./bin/bp3 warden --bad-flag`.
   - *Result:* Empty dirs / `--no-sessions` exit `0` with `sessions_scanned: 0` (Layer 1 still runs); unknown quest exits `2` (`E_NOT_FOUND`); bad flag exits `2` (`E_USAGE`); zero repo mutation.
4. **End-to-end real-repo calibration (true E2E in `dogfood.1`):**
   - *Start:* Real `bp3` repo with the 4 most recent landed quests (including `2026-11-23-fast-agy-induct` and `2026-11-22-induct-inline-as-default-measure-author`).
   - *Action:* `./bin/bp3 warden <q>` on each of the 4 quests and `./bin/bp3 warden --no-sessions`.
   - *Result:* Reproduces all 4 known `2026-11-22` waste classes, `<1s` Layer-1 latency, audited precision `>= 80%` (`<= 20%` FP) recorded in `LOG.md` / `FEEDBACK.md`.
