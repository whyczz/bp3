---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# sqlite-control-plane: machine-local SQLite DB, repo registry, and cross-repo drop queue

TL;DR
Stand up a single machine-local SQLite database (`~/.local/share/bp3/bp3.sqlite`, WAL mode, `busy_timeout = 5000`, `PRAGMA user_version` migrations) inside `bp3-q` via OCaml's `sqlite3` binding — completely additive, touching zero `refs/heads/bp3/*` quest ledgers or existing tests. Ship two immediate cross-repo primitives on top of it: a **repo registry** (`bp3 repo add|list|remove`) tracking every local repo (`bp3`, `predictor`, `esc2`/`esc3`, …) and an atomic **cross-repo drop queue** (`bp3 drop add|list|claim|done|dismiss`) so a session in `predictor` can drop a `bp3` bug or feature request without dirtying `~/m/bp3`'s working tree or colliding with an active quest branch. Teach `/warden` and `using-bp3` to route cross-repo drops through `bp3 drop`. Companion Quest 2 (`docs/quests/2026-11-23-sqlite-quest-store/QUEST.md`) migrates `refs/heads/bp3/*` and adds `bp3 db backup`.

ELI5
Right now `bp3` only knows about one git repo at a time. When you're building in `predictor` and hit a `bp3` bug, there's nowhere safe to drop it without walking into `~/m/bp3` and risking a dirty branch. This quest gives your MacBook one shared local SQLite database (`~/.local/share/bp3/bp3.sqlite`) where all your repos register themselves and drop work items for each other safely, with atomic claims so future subagents can pull items without stepping on each other. Existing quest state in git stays 100% untouched until Quest 2.

## Context

Promotes `docs/icebox/2026-11-18-sqlite-store.md` (copied verbatim to [ICEBOX.md](ICEBOX.md) and removed from `docs/icebox/`). `docs/icebox/2026-11-17-tape-scraper-sqlite.md` remains frozen (raw-tape FTS5 mining is not part of this quest).

Owner drivers (2026-11-23 red chair + scoping):
1. **Cross-repo drop queue on one MacBook:** Multiple local repos (`bp3`, `predictor`, `esc2`/`esc3`, future apps) need a shared inbox so feedback in a downstream repo can split cleanly between the app itself and `bp3` control-plane fixes/features.
2. **Single-machine reality:** No cloud runners or remote workers — everything runs locally on macOS (phone access via Antigravity / Claude / Codex remote control). Apple's `libsqlite3.dylib` lives in the macOS dyld shared cache alongside `libSystem.B.dylib`, removing cross-host packaging friction.
3. **Future subagent trees:** Preparing an ACID WAL primitive (`BEGIN IMMEDIATE`) so future `pi` / `agy` subagent-tree experiments can claim work atomically — without pre-building speculative subagent tables before a spike proves what they need (Gall's law, `CONTEXT.md:80`).
4. **Two-quest split settled by owner (2026-11-23):** `"yeah i like this -> we should break this up into two quests"`, `"yep i like bp3 db backup -> that should be the 2nd quest?"`, `"yep, lgtm, lets /quest both"`.

Measured ground (read 2026-11-23):

| Fact | Source |
|---|---|
| `CONSTRAINTS.md:21` lists OCaml libs `stdlib unix str yojson ounit2 qcheck-core qcheck-ounit`; `sqlite3` is not yet listed and `opam list --installed` has no sqlite package | `CONSTRAINTS.md:21`, `opam list` |
| `_build/default/src/quest/main.exe` links only `/usr/lib/libSystem.B.dylib`; macOS ships `/usr/bin/sqlite3` 3.54.0 and `libsqlite3.dylib` in the dyld shared cache | `otool -L`, `sqlite3 --version` |
| Local `refs/heads/bp3/*` count = 195 vs `origin/bp3/*` = 3 (192 never pushed to remote) | `git for-each-ref`, `git branch -r` |
| `bin/bp3:378-395` dispatches top-level doors (`q`, `n`, `e`, `warden`, `harness`, `config`, `worktree`, `init-repo`, `init`, `skills`); `db`, `repo`, `drop` do not exist today | `bin/bp3:368-396`, `src/quest/main.ml:750-795` |
| `Store.reserved_slugs` (`src/quest/store.ml:18-24`) guards door/verb spellings against quest/node slug collisions; `db`, `repo`, `drop` must be reserved | `src/quest/store.ml:18-24` |

## Terms

| Term | Meaning |
|---|---|
| `BP3_DB` | env var overriding the SQLite DB path (mandatory for test isolation so tests never touch the user's real DB); default `$XDG_DATA_HOME/bp3/bp3.sqlite` else `$HOME/.local/share/bp3/bp3.sqlite` |
| `bp3.sqlite` | single machine-local SQLite database in WAL mode (`journal_mode=WAL`, `busy_timeout=5000`, `foreign_keys=ON`), versioned by `PRAGMA user_version` |
| `db` door | top-level CLI door `bp3 db info [--format json\|table]` and `bp3 db -h`; reports resolved DB path, schema version, journal mode, and table row counts |
| `repo` door | top-level CLI door `bp3 repo add [<path>] [--name <slug>]`, `bp3 repo list [--format json\|table]`, `bp3 repo remove <name>` managing the `repos` table |
| `repo_name` | unique kebab-case slug identifying a local git repo on this MacBook (default: lowercased basename of canonical `Unix.realpath` toplevel, e.g. `bp3`, `predictor`, `esc3`) |
| `drop` door | top-level CLI door `bp3 drop add\|list\|claim\|done\|dismiss` managing the cross-repo `drops` queue |
| `drop_status` | lifecycle of a dropped item: `open \| claimed \| done \| dismissed` (`open -> claimed -> done\|dismissed`, or `open -> done\|dismissed`) |
| `drop_kind` | category of a dropped item: `bug \| feature \| note` (default `note`) |
| `E_ALREADY_CLAIMED` | typed refusal (exit 1) when `bp3 drop claim <id>` loses a race or targets a drop not in `open` state, carrying `{id, status, claimed_by}` |
| `E_DB_ERROR` | typed refusal (exit 1) on SQLite open/migration/query failure, carrying `{detail}` |

## Inputs

| Input | Source |
|---|---|
| `BP3_DB` | env var; wins over default `$XDG_DATA_HOME/bp3/bp3.sqlite` / `$HOME/.local/share/bp3/bp3.sqlite`; empty counts as unset |
| `BP3_ROOT` / cwd git toplevel | inferred source repo (`--from`) when omitted on `bp3 drop add` and target path when omitted on `bp3 repo add` |
| `bp3 db info [--format json\|table]` | CLI flags |
| `bp3 repo add [<path>] [--name <slug>]`, `list [--format json\|table]`, `remove <name>` | CLI args/flags |
| `bp3 drop add --to <repo> [--from <repo>] [--kind bug\|feature\|note] --title <text> [--body <text>]` | CLI flags; `--to` and `--title` required |
| `bp3 drop list [--to <repo>] [--from <repo>] [--status open\|claimed\|done\|dismissed\|all] [--format json\|table]` | CLI flags; default `--status open` |
| `bp3 drop claim <id> [--by <owner>]` | CLI args/flags; default `--by` from `BP3_RUN_ID` else `BP3_HARNESS` else `human` |
| `bp3 drop done <id> --reason <text>`, `bp3 drop dismiss <id> --reason <text>` | CLI args/flags; `--reason` required |

## Outputs

| Output | Shape |
|---|---|
| `bp3.sqlite` schema v1 | tables `repos(name PK, root_path UNIQUE, added_at, last_seen_at)` and `drops(id INTEGER PK AUTOINCREMENT, from_repo, to_repo, kind, title, body, status, claimed_by, claimed_at, resolved_at, resolution_reason, created_at)` + index `idx_drops_to_status(to_repo, status)` |
| `bp3 db info` (JSON) | `{"ok":true,"db_path":"...","schema_version":1,"journal_mode":"wal","counts":{"repos":N,"drops_open":M,"drops_total":T}}` |
| `bp3 repo ...` (JSON) | `add`: `{"ok":true,"repo":{"name","root_path","added_at"}}`; `list`: `{"ok":true,"repos":[...]}`; `remove`: `{"ok":true,"removed":"<name>"}` |
| `bp3 drop ...` (JSON) | `add`: `{"ok":true,"drop":{id,from_repo,to_repo,kind,title,body,status:"open",created_at}}`; `list`: `{"ok":true,"drops":[...]}`; `claim`: `{"ok":true,"drop":{...,status:"claimed",claimed_by,claimed_at}}` or exit 1 `E_ALREADY_CLAIMED`; `done`/`dismiss`: `{"ok":true,"drop":{...,status,resolved_at,resolution_reason}}` |
| `--format table` | aligned ASCII tables for `db info`, `repo list`, and `drop list` |
| `skills/warden/SKILL.md` + `skills/using-bp3/SKILL.md` | host-repo `/warden` instructions to route `bp3` bugs/requests via `bp3 drop add --to bp3` and check `bp3 drop list --to <this-repo>` |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 db info
usage: bp3 init ... (unknown door: db)
$ ./bin/bp3 repo list
usage: bp3 init ... (unknown door: repo)
$ ./bin/bp3 drop list
usage: bp3 init ... (unknown door: drop)
$ grep sqlite3 CONSTRAINTS.md
(no match)
```

Design trace (after quest lands):

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 db info
  -> ok:true, schema_version:1, journal_mode:"wal", counts:{repos:0,drops_open:0,drops_total:0}

$ ./bin/bp3 repo add /path/to/bp3 --name bp3
$ ./bin/bp3 repo add /path/to/predictor --name predictor
$ ./bin/bp3 repo list --format table
  -> lists bp3 and predictor with canonical paths

$ ./bin/bp3 drop add --from predictor --to bp3 --kind bug \
    --title "brief omits GRADING.md in host desk" \
    --body "repro in predictor quest-1"
  -> ok:true, drop.id=1, status:"open"

$ ./bin/bp3 drop list --to bp3
  -> returns [drop 1]; working tree of bp3 untouched

$ ./bin/bp3 drop claim 1 --by worker-a
  -> ok:true, status:"claimed", claimed_by:"worker-a"
$ ./bin/bp3 drop claim 1 --by worker-b
  -> rc 1, error.code:"E_ALREADY_CLAIMED", facts:{id:1,status:"claimed",claimed_by:"worker-a"}

$ ./bin/bp3 drop done 1 --reason "fixed in commit abc1234"
  -> ok:true, status:"done", resolution_reason:"fixed in commit abc1234"
$ ./bin/bp3 drop list --to bp3
  -> returns [] (default filters --status open)

$ make check-full
  -> rc 0 (existing refs/heads/bp3/* tests untouched and green; check-constraints green)
```

## Goal and why

Give `bp3` a real local SQLite foundation (`bp3.sqlite`) and solve the immediate multi-repo pain on a single MacBook: working across `bp3`, `predictor`, `esc2`/`esc3`, and future apps without dirtying one repo's working tree when another repo discovers a bug or feature request for it. Proving `sqlite3-ocaml`, WAL concurrency, and `PRAGMA user_version` migrations on additive tables first keeps Quest 1 zero-breakage and de-risks Quest 2's full ledger migration.

## Success picture

- `CONSTRAINTS.md` records the owner's sign-off for OCaml `sqlite3` and the `bp3 db`/`repo`/`drop` CLI surfaces; `scripts/check-constraints` passes.
- `bp3-q` compiles with `sqlite3` (linking only system `libSystem.B.dylib` + `libsqlite3.dylib` on macOS, zero Homebrew runtime dep) and initializes `~/.local/share/bp3/bp3.sqlite` cleanly on first use with WAL + `busy_timeout = 5000` + `PRAGMA user_version = 1`.
- Any repo on the MacBook can register via `bp3 repo` and drop/list/atomically-claim/resolve cross-repo items via `bp3 drop` with typed JSON verdicts and `--format table` views.
- Concurrent `bp3 drop claim <id>` stress test proves exactly one claimant succeeds and all others receive `E_ALREADY_CLAIMED` (zero SQLite `SQLITE_BUSY` crashes).
- `/warden` and `using-bp3` document cross-repo dropping so downstream repos like `predictor` route `bp3` bugs straight into `bp3 drop add --to bp3`, rendered across all harnesses.
- Zero regressions to `bp3 q`, `bp3 metrics`, `bp3 warden`, or any existing `refs/heads/bp3/*` suite.

## Scope

| In | Out |
|---|---|
| `CONSTRAINTS.md` sign-off + opam `sqlite3` binding + `src/quest/db.ml` (WAL, `busy_timeout`, `PRAGMA user_version` v1) | Migrating `refs/heads/bp3/*`, `.git/bp3/`, or `.bp3/desks/` into SQLite (Quest 2: `2026-11-23-sqlite-quest-store`) |
| `bp3 db info`, `bp3 repo add\|list\|remove`, `bp3 drop add\|list\|claim\|done\|dismiss` + `-h` help + `Store.reserved_slugs` | `bp3 db backup` / `bp3 db check` / iCloud or Google Drive snapshot copy (Quest 2, when SQLite becomes quest truth) |
| Unit tests (`test_db.ml`, `test_drop.ml`) + fixture & concurrent-claim tests (`test/repo.sh`, `test/drop.sh`) using `BP3_DB` temp isolation | Subagent tree / blackboard tables (deferred until a `pi`/`agy` subagent-tree spike settles the real schema) |
| Skill updates (`skills/warden/SKILL.md`, `skills/using-bp3/SKILL.md`, renders, `AGENTS.md`/`CLAUDE.md`) as dedicated `skills.1` node | Raw tape FTS5 miner (`docs/icebox/2026-11-17-tape-scraper-sqlite.md`, stays frozen) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):**
  - Adds `sqlite3` to `lang ocaml ... libs` (`CONSTRAINTS.md:21`) and `bp3 db`, `bp3 repo`, `bp3 drop` to the `bp3 CLI` row in Surfaces (`CONSTRAINTS.md:49`).
  - `/teach` pitch delivered 2026-11-23 (before/change/after, cost of 1 opam dep + macOS system `libsqlite3.dylib`, boring alternatives of plain JSON files in `~/.local/share/bp3/inbox/` or shelling out to `/usr/bin/sqlite3`).
  - Owner words recorded 2026-11-23: `"yep, lgtm, lets /quest both"` (in response to the `/teach` pitch and 2-quest split). `db.1` adds the dated Sign-off log row quoting those exact words alongside editing `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Databases earn their keep with concurrent writers and cross-repo coordination (`CONTEXT.md:33`: Invoker runs SQLite; Beads moved off JSONL). Here single-MacBook cross-repo drops + atomic `BEGIN IMMEDIATE` claims justify WAL SQLite with **no daemon** (`CONTEXT.md:34`).
  - Gall's law (`CONTEXT.md:80`): ship small additive tables first (`repos`, `drops`) instead of a big-bang rewrite or speculative subagent tables.

## Human touchpoints

| When | Owner |
|---|---|
| Approve frame (or settle any red-ink tweaks on CLI verbs / schema) | owner |
| Promotion (`goal_fin`) | owner |

## Nodes

### Milestone: db

| Node | TL;DR |
|---|---|
| [db.1 - sqlite-foundation](nodes/node-db-1-sqlite-foundation/NODE.md) | `CONSTRAINTS.md` sign-off + opam `sqlite3` dep + `src/quest/db.ml` (`BP3_DB` / `~/.local/share/bp3/bp3.sqlite`, WAL, `busy_timeout`, `PRAGMA user_version` v1) + `bp3 db info` + `test/unit/test_db.ml` |

### Milestone: repo

| Node | TL;DR |
|---|---|
| [repo.1 - repo-registry](nodes/node-repo-1-repo-registry/NODE.md) | `src/quest/repo_store.ml` + `bp3 repo add\|list\|remove` (canonical realpath identity, auto-register helper, `--format json\|table`) + `test/repo.sh` |

### Milestone: drop

| Node | TL;DR |
|---|---|
| [drop.1 - cross-repo-drop-queue](nodes/node-drop-1-cross-repo-drop-queue/NODE.md) | `src/quest/drop_store.ml` + `bp3 drop add\|list\|claim\|done\|dismiss` (atomic `BEGIN IMMEDIATE` claim with `E_ALREADY_CLAIMED`, `--to`/`--from`/`--kind`/`--status`/`--format`) + concurrent-claim fixture `test/drop.sh` + `test/unit/test_drop.ml` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - cross-repo-drop-skills](nodes/node-skills-1-cross-repo-drop-skills/NODE.md) | update `skills/warden/SKILL.md` (host-mode `/warden` drops `bp3` bugs via `bp3 drop add --to bp3`), `skills/using-bp3/SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `completions/_bp3`; re-render all harnesses + `test/skills.sh` |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| macOS binary linking | only `libSystem.B.dylib` + system `libsqlite3.dylib` (zero Homebrew runtime dylibs) | `otool -L _build/default/src/quest/main.exe` |
| concurrent claim safety | 10 parallel `bp3 drop claim <id>` processes -> exactly 1 `ok:true`, 9 `E_ALREADY_CLAIMED`, 0 `E_DB_ERROR` | `test/drop.sh` |
| `bp3 drop list` latency | `< 50ms` warm on 100 drops | timed run |
| regression check | 100% of existing `make check-full` suites green untouched | `make check-full` |

## Risks and red chair

- **Strongest attack (tests polluting real `~/.local/share/bp3/bp3.sqlite`):** "Running `make check-full` or parallel `run-suites` without isolating the DB path will scribble test drops into the owner's real MacBook database."
  - **Settled in design:** `db.1` implements `BP3_DB` override, and `test/repo.sh` / `test/drop.sh` / OCaml unit tests always point `BP3_DB` at a fresh temp file (never `$HOME`). `db.1` also checks `XDG_DATA_HOME` before `$HOME/.local/share` so sandboxed callers stay isolated automatically.
- **Second attack (opam `sqlite3` build snag with macOS SDK):** "Recall `Makefile:3-6` pins `MacOSX26.5.sdk` because `MacOSX27.2.sdk` has a broken `libpthread.tbd`. Installing `opam install sqlite3` could trip on the same SDK or link Homebrew's sqlite instead of Apple's."
  - **Settled in design:** `db.1` acceptance gate explicitly verifies `SDKROOT` build via `make check` AND checks `otool -L _build/default/src/quest/main.exe` to confirm no accidental `/opt/homebrew/` dylib coupling (or documents exact build env if pkg-config needs flags).
- **Attack on source (`ICEBOX.md` + owner prompt):**
  - *Icebox assumption rejected:* `ICEBOX.md` proposed `.git/bp3/bp3.sqlite` per-repo to fix JSON races in `.git/bp3/` and speed up `bp3 g r`. Rejected with live evidence: `.git/bp3/` hasn't had a write since Nov 18 and `codebase-diet` is deleting `harness.ml`. The real trigger is a **machine-local cross-repo DB** (`~/.local/share/bp3/bp3.sqlite`), so `bp3.sqlite` lives in `$XDG_DATA_HOME/bp3/`, not `.git/bp3/`.
  - *Premature subagent tables rejected:* Owner wants to explore `pi`/`agy` subagent trees, but designing subagent tables before spiking context-sharing risks another unused `harness.ml` (Gall's law). Settled by omitting subagent tables from Quest 1 and keeping schema v1 minimal (`repos` + `drops`).

## Open questions

1. On `bp3 drop add --to <repo>`, should an unregistered `--to` repo name be **accepted** (free-form slug so you can drop for `esc3` before cloning it) or **refused** unless registered in `repos`? — **owner** (recommended: accept any valid slug and optionally warn `W_REPO_UNREGISTERED`, so dropping never blocks when a repo isn't registered yet).
2. Should `bp3 drop` also support `reopen <id>` or `unclaim <id>` in v1, or keep transitions strictly `open -> claimed -> done|dismissed` for now? — **owner** (recommended: add `unclaim` only if a subagent spike needs lease release; keep v1 to `add|list|claim|done|dismiss`).

## Node diagram

```text
db.1 (CONSTRAINTS + opam sqlite3 + src/quest/db.ml + bp3 db info)
  ├──► repo.1 (bp3 repo add|list|remove)
  └──► drop.1 (bp3 drop add|list|claim|done|dismiss + atomic WAL race test)
         └──► skills.1 (warden + using-bp3 + AGENTS/CLAUDE + renders)
```
