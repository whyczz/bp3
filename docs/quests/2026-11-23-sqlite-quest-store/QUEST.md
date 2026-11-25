---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: major
---

# sqlite-quest-store: migrate quest ledgers, metrics, and runtime state into bp3.sqlite + bp3 db backup

TL;DR
Complete the move off hidden git refs (`refs/heads/bp3/{quest,node}/*`) and untracked local JSON dirs (`.git/bp3/*`, `.bp3/desks/*.json`) into the single machine-local SQLite database (`~/.local/share/bp3/bp3.sqlite`) built in Quest 1 (`2026-11-23-sqlite-control-plane`). Ship **`bp3 db backup`** (`VACUUM INTO` clean snapshot copied to a configured Google Drive / iCloud Drive / local `backup_dir` with rolling retention) and **`bp3 db check`** FIRST so the safety net is live before any migration. Then ship an idempotent ref importer (`bp3 db import-refs`) and optional flat quest exporter (`bp3 db export-quest`), cut `Store`, `Metrics_io`, `Config`, `Worktree` desk registry, `Warden_io`, and `scripts/agy-statusline` over to SQLite (`quests`, `nodes`, append-only `ledger_events`, `metrics`, `desks`, `kv_config`), delete the `hash-object`/`commit-tree`/`update-ref` + legacy-ref fold plumbing, migrate the 12 ref-reading test suites to `BP3_DB`-isolated assertions, and update docs/skills. Git keeps code, worktrees, and authored docs (`QUEST.md`, `NODE.md`, `LOG.md`, `FEEDBACK.md`, `plans/`).

ELI5
Today `bp3` secretly maintains 195 hidden git branches (`refs/heads/bp3/*`) just to store quest state and metrics — spawning 6 git commands per write even though 192 of those 195 branches are never pushed to GitHub. After Quest 1 stands up `bp3.sqlite` for cross-repo tickets, this quest moves all quest ledgers, metrics, config, and desk metadata into that same SQLite database, adds one-command safe backups (`bp3 db backup`) to Google Drive or iCloud Drive, imports your existing local quest history, and deletes the git-as-a-database plumbing. Git goes back to doing what git is best at: code, worktrees, and markdown docs.

## Context

Companion to `docs/quests/2026-11-23-sqlite-control-plane/QUEST.md` (which holds the verbatim promoted icebox entry at `docs/quests/2026-11-23-sqlite-control-plane/ICEBOX.md`, originally `docs/icebox/2026-11-18-sqlite-store.md`).

Sequenced **after**:
1. `docs/quests/2026-11-23-sqlite-control-plane/` (provides OCaml `sqlite3`, `src/db/` [`bp3_db`], `BP3_DB`, schema v1, `repos`, and `tickets`).
2. `docs/quests/2026-11-23-codebase-diet/` (deletes ~2,600 LOC of unused `harness.ml` supervisor/link/tape/watch subsystems so we do not migrate dead `.git/bp3/` directories).
3. `docs/quests/2026-11-23-warden-v0/` (so `Warden_io` cutover happens once cleanly).

Measured ground (read 2026-11-23):

| Fact | Source |
|---|---|
| Local `refs/heads/bp3/*` refs = **195** across 34 quests / 158 nodes; remote `origin/bp3/*` tracking refs = **3** (ancient Nov 5 test branches; 192 of 195 never pushed) | `git for-each-ref`, `git branch -r`, `bp3 q r` |
| Every state write in `src/quest/gitx.ml:217-240` spawns `read-tree`, `hash-object`, `update-index`, `write-tree`, `commit-tree`, `update-ref` just to append one line to `ledger.jsonl` / `state.yaml` / `metrics.jsonl` | `src/quest/gitx.ml:217-253` |
| `src/quest/store.ml:253-348` carries ~100 lines of multi-era ref/path folding (`legacy_quest_ref_kinds`, `legacy_node_ledger_paths`, `pick_longest`) solely because storage-branch trees were never rewritten on renames | `src/quest/store.ml:253-348`, `src/quest/layout.ml:9-32` |
| `bp3 q r` (all 34 quests) takes `0.87s` warm (`1.73s` cold); single quest `bp3 q r <q>` takes `0.135s` | timed runs (2026-11-23) |
| **12 test files** (68 occurrences) read `refs/heads/bp3/*` directly (`test/blocked.sh`, `context.sh`, `diagram.sh`, `g.sh`, `hooks.sh`, `induct-grade.test.mjs`, `metrics.sh`, `ready.sh`, `tape.sh`, `worktree.sh`, `unit/test_layout.ml`, `unit/samples/README.md`) plus `scripts/agy-statusline:236` | `git grep` (2026-11-23) |
| Reverses two earlier single-repo decisions (`engine-core QUEST.md:195` "no SQLite Board"; `supervisor QUEST.md:279` "SQLite/Redis as truth" out of scope) — explicitly re-decided by owner on 2026-11-23 for the single-MacBook multi-repo architecture | owner decision (2026-11-23) |

## Terms

| Term | Meaning |
|---|---|
| `schema v2` | `PRAGMA user_version = 2` adding `quests`, `nodes`, `ledger_events`, `metrics`, `desks`, `kv_config` tables to `bp3.sqlite` (all keyed by `repo_id` from Quest 1's `repos`) |
| `ledger_events` | append-only SQL table preserving `bp3`'s "ledger is truth" invariant (`id PK`, `repo_id`, `quest`, `node`, `ts`, `edge`, `from_st`, `to_st`, `cycle`, `commit_sha`, `verdict`, `reason`, `harness`, `model`, `bp3_version`, `run_id`, `checkpoint`, `extra_json`); never updated or deleted |
| `backup_dir` | user-configured destination directory for `bp3 db backup` (e.g., Google Drive `~/Library/CloudStorage/GoogleDrive-.../My Drive/bp3-backups` or iCloud Drive `~/Library/Mobile Documents/com~apple~CloudDocs/bp3-backups`); stored in `kv_config` (`backup_dir`) or overridden by `BP3_BACKUP_DIR` / `--to <dir>` |
| `bp3 db backup` | takes a consistent single-file snapshot via SQLite `VACUUM INTO` on local APFS temp storage, verifies `PRAGMA integrity_check`, copies to `<backup_dir>/bp3-YYYY-MM-DD.sqlite` and `<backup_dir>/bp3-latest.sqlite`, and prunes daily snapshots beyond `--keep N` (default 14) |
| `bp3 db check` | runs `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, and schema version validation; exits 0 when healthy, 1 (`E_DB_CORRUPT`) on any failure |
| `bp3 db import-refs` | idempotent importer reading `refs/heads/bp3/{quest,node,graph,goal,exp}/*` ledgers + `metrics.jsonl` from a git repo into `bp3.sqlite`, verifying folded state parity against every imported node |
| `bp3 db export-quest` | writes flat `ledger.jsonl` and `metrics.jsonl` snapshots for a quest (for archival / PR attachment at `goal_fin`) without mutating DB state |
| `E_DB_CORRUPT` | typed refusal (exit 1) when `bp3 db check` or pre-backup integrity verification fails |
| `E_BACKUP_CONFIG` | typed refusal (exit 2) when `bp3 db backup` runs with no `--to`, no `BP3_BACKUP_DIR`, and no configured `backup_dir` |

## Inputs

| Input | Source |
|---|---|
| `BP3_DB` / `~/.local/share/bp3/bp3.sqlite` | from Quest 1 (`src/db/db.ml`) |
| `BP3_BACKUP_DIR` / `--to <dir>` / `kv_config.backup_dir` | precedence: `--to` > `BP3_BACKUP_DIR` > `kv_config.backup_dir` |
| `--keep <N>` | `bp3 db backup` daily snapshot retention count (default `14`, must be `>= 1`) |
| `bp3 db import-refs [--repo <path>]` | reads legacy & canonical `refs/heads/bp3/*` refs from target git repo (default current repo) |
| `bp3 db export-quest <quest> [--out <dir>]` | exports quest + node ledgers & metrics as flat JSONL |
| All existing `bp3 q`, `bp3 metrics`, `bp3 warden`, `bp3 config`, `bp3 harness desk` calls | unchanged CLI syntax and JSON verdict contracts |

## Outputs

| Output | Shape |
|---|---|
| `bp3 db backup` (JSON) | `{"ok":true,"source":"...","snapshot":"<dir>/bp3-YYYY-MM-DD.sqlite","latest":"<dir>/bp3-latest.sqlite","bytes":N,"integrity":"ok","pruned":[...]}` |
| `bp3 db check` (JSON) | `{"ok":true,"db_path":"...","schema_version":2,"integrity":"ok","foreign_keys":"ok","counts":{...}}` |
| `bp3 db import-refs` (JSON) | `{"ok":true,"repo":"...","quests_imported":Q,"nodes_imported":N,"ledger_rows":L,"metric_rows":M,"skipped_existing":S,"parity_ok":true}` |
| `bp3 db export-quest <q>` (JSON) | `{"ok":true,"quest":"<q>","out_dir":"...","files":[...]}` |
| `bp3 q` / `bp3 metrics` / `bp3 warden` / `bp3 config` / `bp3 harness desk` | **same JSON/table/tree verdict schemas**, now backed by `bp3.sqlite` with zero new `refs/heads/bp3/*` writes |
| `scripts/agy-statusline` | reads quest creation timestamp via `bp3 q r <quest>` (new `created_at` field) instead of `git show refs/heads/bp3/...` |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 db backup
usage: bp3 init ... (unknown door: db)
$ git for-each-ref refs/heads/bp3/ | wc -l
195
$ grep -n "refs/heads/bp3" scripts/agy-statusline
236:first_ts="$(git -C "$root" show "refs/heads/bp3/quest/${quest}:docs/quests/${quest}/ledger.jsonl" ...
```

Design trace (after quest lands):

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ BACKUP_DIR="$(mktemp -d)"

# 1. Import existing local refs idempotently with parity check
$ ./bin/bp3 db import-refs
  -> ok:true, quests_imported:34, nodes_imported:158, parity_ok:true
$ ./bin/bp3 db import-refs
  -> ok:true, quests_imported:0, skipped_existing:34, parity_ok:true (idempotent)

# 2. Backup cleanly to Google Drive / iCloud Drive / any local dir via VACUUM INTO
$ ./bin/bp3 db backup --to "$BACKUP_DIR" --keep 7
  -> ok:true, integrity:"ok", creates bp3-YYYY-MM-DD.sqlite + bp3-latest.sqlite
  -> zero -wal or -shm files inside "$BACKUP_DIR"
$ ./bin/bp3 db check
  -> ok:true, schema_version:2, integrity:"ok", foreign_keys:"ok"

# 3. Full FSM lifecycle writes zero git refs
$ ./bin/bp3 q c demo --type default
$ ./bin/bp3 q demo n c node-1
$ ./bin/bp3 q demo n node-1 e handoff --commit HEAD --reason "ready"
$ git for-each-ref refs/heads/bp3/quest/demo refs/heads/bp3/node/demo/
  -> empty (zero hidden refs created!)

# 4. Statusline + full test pyramid green with isolated temp BP3_DB per suite
$ make check-full
  -> rc 0 (faster than pre-SQLite baseline; ~/.local/share/bp3/bp3.sqlite untouched)
```

## Goal and why

Eliminate git-as-a-database plumbing (`read-tree` + `hash-object` + `update-index` + `write-tree` + `commit-tree` + `update-ref` on every transition, 195 unpushed hidden refs, and ~100 lines of multi-era ref-path folding) while giving the owner a single, queryable, ACID, cloud-backed SQLite store across every repo on their MacBook. Putting `bp3 db backup` first guarantees that when `bp3.sqlite` becomes quest truth, daily consistent snapshots to Google Drive or iCloud Drive are already tested and running.

## Success picture

- `bp3 db backup` safely creates a single-file `VACUUM INTO` snapshot (verified with `PRAGMA integrity_check`) on local APFS and copies it to any configured `backup_dir` (Google Drive, iCloud Drive, or local path) with zero `-wal`/`-shm` sidecars and automatic daily pruning; `bp3 db check` validates DB health.
- `bp3 db import-refs` idempotently imports every existing local quest and node ref (both canonical and legacy `graph`/`goal`/`exp` eras) from `bp3` and downstream repos like `predictor` with 100% state-fold parity.
- All `bp3 q`, `bp3 metrics`, `bp3 warden`, `bp3 config`, and `bp3 harness desk` operations run against `bp3.sqlite` with zero new `refs/heads/bp3/*` refs written, preserving exact JSON verdict shapes and git-enforced code invariants (`E_DIRTY_TREE`, `E_COMMIT_MISMATCH`, `Brief` reading files at `--commit <sha>`, real git worktree desks).
- `gitx.ml` ledger plumbing (`commit_files`, `move_ref`, `create_branch_commit`, `cat-file --batch`) and `store.ml` legacy ref/path folding are deleted; `scripts/agy-statusline` no longer shells out to `git show refs/heads/bp3/...`.
- All 12 migrated test suites pass under parallel `make check-full` with per-suite isolated `BP3_DB`, never touching the user's real `~/.local/share/bp3/bp3.sqlite`.

## Scope

| In | Out |
|---|---|
| Schema v2 (`quests`, `nodes`, `ledger_events`, `metrics`, `desks`, `kv_config`) + `bp3 db backup` (`VACUUM INTO` -> `backup_dir` + pruning) + `bp3 db check` (`backup.1`) | Putting the live WAL database directly inside Google Drive or iCloud Drive (explicitly forbidden; snapshots only) |
| Idempotent `bp3 db import-refs` (all eras) + `bp3 db export-quest` (`migrate.1`) | Auto-deleting existing local `refs/heads/bp3/*` during import (refs stay untouched until the owner explicitly prunes them after verifying import!) |
| Cutover of `Store`, `Metrics_io`, `Config`, `Worktree` desk registry, `Warden_io`, and `scripts/agy-statusline` to SQLite + deleting git-ref ledger plumbing (`store.1`) | Replacing real `git worktree` checkouts, git commits, `QUEST.md`/`NODE.md`/`LOG.md`/`FEEDBACK.md`, or `plans/*.yaml` (those stay in Git) |
| Migrating the 12 ref-reading test suites + enforcing per-suite temp `BP3_DB` in `run-suites` (`tests.1`) | Subagent tree / blackboard tables or FTS5 raw-tape scraper (separate future quest once spiked) |
| Updating `AGENTS.md`, `CLAUDE.md`, `skills/using-bp3`, `skills/warden`, `completions/_bp3` + re-renders (`skills.1`) | Cloud sync daemon or multi-machine replication |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages or libraries beyond Quest 1 (`sqlite3` already signed off in Quest 1). Adds `bp3 db backup`, `bp3 db check`, `bp3 db import-refs`, `bp3 db export-quest` under the existing `bp3 db` CLI surface.
- **Common-sense pass (`CONTEXT.md`):**
  - Reverses earlier "git refs for ledgers" choice explicitly because 192/195 refs are local-only on a single MacBook and the owner runs zero cloud runners.
  - Preserves "no daemon" (`CONTEXT.md:34`): `bp3 db backup` is an explicit command (or `/warden` hook / user `/schedule`), never a background sync daemon.
  - Preserves "Ledger is truth" (`AGENTS.md`): `ledger_events` is strictly append-only; `nodes` state is derived/updated transactionally inside the same `BEGIN IMMEDIATE` transaction as the ledger insert.

## Human touchpoints

| When | Owner |
|---|---|
| Approve frame (confirming `bump: major` and reversal of `engine-core:195` / `supervisor:279`) | owner |
| Configure personal `backup_dir` (Google Drive or iCloud Drive path) after `backup.1` / promotion | owner |
| Promotion (`goal_fin`) + optional one-time local `refs/heads/bp3/*` cleanup after verifying `bp3 db import-refs` on `bp3` and `predictor` | owner |

## Nodes

### Milestone: backup

| Node | TL;DR |
|---|---|
| [backup.1 - db-backup-and-check](nodes/node-backup-1-db-backup-and-check/NODE.md) | schema v2 DDL (`quests`, `nodes`, `ledger_events`, `metrics`, `desks`, `kv_config`) + `bp3 db backup [--to <dir>] [--keep N]` (`VACUUM INTO` local tmp -> integrity check -> copy to Google Drive / iCloud Drive / `backup_dir` + daily pruning) + `bp3 db check` + `test/db-backup.sh` |

### Milestone: migrate

| Node | TL;DR |
|---|---|
| [migrate.1 - import-git-refs-and-export](nodes/node-migrate-1-import-git-refs-and-export/NODE.md) | idempotent `bp3 db import-refs [--repo <path>]` (imports canonical + legacy `graph`/`goal`/`exp` refs and `metrics.jsonl` with fold-state parity verification) + `bp3 db export-quest <quest>` + `test/db-migrate.sh` |

### Milestone: store

| Node | TL;DR |
|---|---|
| [store.1 - sqlite-quest-and-metrics-engine](nodes/node-store-1-sqlite-quest-and-metrics-engine/NODE.md) | cut `Store`, `Metrics_io`, `Config`, `Worktree` desk registry, `Warden_io`, and `scripts/agy-statusline` over to `bp3.sqlite` (append-only `ledger_events`, `BEGIN IMMEDIATE` + `E_STALE_WORLD` optimistic seq check, same JSON verdicts); delete `commit_files`/`move_ref`/`cat-file --batch` ledger plumbing and `legacy_*` ref folding |

### Milestone: tests

| Node | TL;DR |
|---|---|
| [tests.1 - migrate-fixture-suites](nodes/node-tests-1-migrate-fixture-suites/NODE.md) | enforce per-suite temp `BP3_DB` in `src/quest/run_suites.ml` and migrate the 12 test suites (68 direct `refs/heads/bp3/*` assertions) to `bp3 q` / `bp3 db` assertions; prove `make check-full` green and faster |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - docs-and-skills-cutover](nodes/node-skills-1-docs-and-skills-cutover/NODE.md) | update `AGENTS.md`, `CLAUDE.md`, `skills/using-bp3/SKILL.md`, `skills/warden/SKILL.md` (add `bp3 db backup` at quest landing), and `completions/_bp3`; re-render all harnesses + `test/skills.sh` |

## Scorecard

| Row | Baseline (2026-11-23) | Target | Read from |
|---|---|---|---|
| `bp3 q r` (all 34 quests) warm latency | `0.868s` | **< `0.25s`** (with `commit_changes` only when needed or cached per SHA) | timed run |
| hidden `refs/heads/bp3/*` created on new quest | 1 per quest + 1 per node | **0** | `git for-each-ref` |
| import parity across existing 34 quests / 158 nodes | n/a | **100%** state/cycle/commit/metrics match | `bp3 db import-refs` |
| backup snapshot hygiene | n/a | single self-contained `.sqlite` passing `PRAGMA integrity_check`, zero `-wal`/`-shm` in `backup_dir` | `test/db-backup.sh` |
| `src/quest/gitx.ml` + `store.ml` plumbing cut | ~350 LOC git-ref plumbing + legacy fold | deleted cleanly | `wc -l` / `git diff --stat` |

## Risks and red chair

- **Strongest attack (data loss during cutover or cloud-sync corruption):** "If `bp3.sqlite` corrupts or gets lost on disk, all quest ledgers across every repo vanish — whereas git refs lived inside `.git/objects/`."
  - **Settled in design:** Three layered defenses: (1) `backup.1` ships **before** any migration (`VACUUM INTO` -> `PRAGMA integrity_check` -> copy to Google Drive / iCloud Drive, never live WAL in cloud folders), (2) `migrate.1` never deletes existing local `refs/heads/bp3/*` during import so rollback is instant, and (3) `bp3 db export-quest` can emit flat `ledger.jsonl`/`metrics.jsonl` snapshots at `goal_fin` if desired.
- **Second attack (parallel test suites clobbering each other or the owner's real DB):** "Today each shell fixture creates a temp git repo, which automatically isolates `refs/heads/bp3/*`. With a machine-global default `~/.local/share/bp3/bp3.sqlite`, every fixture test would collide on the same DB!"
  - **Settled in design:** `tests.1` makes `src/quest/run_suites.ml` set a fresh per-suite temp `BP3_DB` in the child environment for every suite automatically (and `test/unit/` tests always use temp paths), plus `bp3 db backup` refuses if `BP3_DB` points inside a cloud sync folder.
- **Third attack (`store.1` + `tests.1` chicken-and-egg gate breakage):** "If `store.1` switches `bp3 q` off git refs before `tests.1` updates the 12 fixture suites that run `git show bp3/node/...:ledger.jsonl`, `store.1` cannot pass `make check-full`!"
  - **Settled in design:** `store.1` and `tests.1` are explicitly noted: either `store.1` passes unit tests + new SQLite fixtures while `tests.1` completes the legacy-ref fixture cutover on the same quest branch (or `store.1` keeps a temporary read-only shim / `tests.1` folds the ref-assertion updates cleanly before `make check-full` — tracked cleanly in `store.1` and `tests.1` acceptance gates; see Open question 1).
- **Attack on source (reversal of `engine-core:195` and `supervisor:279`):**
  - *Checked against live reality:* 192 of 195 `refs/heads/bp3/*` refs were never pushed to `origin`, the owner runs 100% locally on one MacBook with zero cloud runners, and `git update-ref` only covered single-repo state. Reversal is justified by observed evidence, not preference.

## Open questions

1. Should `store.1` + `tests.1` land as **one combined high-blast-radius node** (so every single commit keeps `make check-full` 100% green without a temporary flag), or two nodes using a temporary `BP3_STORE=sqlite` opt-in during `store.1` that flips to default-only in `tests.1`? — **owner** (recommended: temporary `BP3_STORE=sqlite` in `store.1` flipped to SQLite-only + ref-plumbing deletion in `tests.1`, so every node commit passes `make check-full` cleanly with zero red commits!).
2. At quest landing (`/warden` `goal_fin`), should `/warden` automatically run `bp3 db backup` (when `backup_dir` is configured) AND optionally `bp3 db export-quest <q>` into `docs/quests/<q>/`? — **owner** (recommended: auto-run `bp3 db backup` when configured; keep `export-quest` opt-in so `docs/quests/` stays clean).
3. On `bp3 q r` (all quests), should `commit_changes` (`git diff-tree`) still run for landed quests or be omitted on landed quests / cached by `(repo_id, commit_sha)` in SQLite so all-quests `bp3 q r` drops from `0.87s` to `< 0.05s`? — **owner** (recommended: cache `(repo_id, commit_sha) -> changes_json` in a tiny `commit_changes_cache` table since commit diffs are immutable by SHA!).

## Node diagram

```text
(after 2026-11-23-sqlite-control-plane, codebase-diet, and warden-v0)

backup.1 (schema v2 + bp3 db backup VACUUM INTO + bp3 db check)
   ──► migrate.1 (bp3 db import-refs + bp3 db export-quest)
   ──► store.1 (SQLite Store/Metrics/Config/Worktree/Warden/statusline)
   ──► tests.1 (per-suite BP3_DB + migrate 12 suites + delete git-ref plumbing)
   ──► skills.1 (AGENTS/CLAUDE + using-bp3 + warden backup hook + renders)
```
