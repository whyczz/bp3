---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# sqlite-control-plane: machine-local SQLite DB, repo registry, and cross-repo ticket queue

TL;DR
Stand up a single machine-local SQLite database (`~/.local/share/bp3/bp3.sqlite`, WAL mode, `busy_timeout = 5000`, `PRAGMA user_version` migrations) inside `bp3-q` via OCaml's `sqlite3` binding — completely additive, touching zero `refs/heads/bp3/*` quest ledgers or existing tests. Ship two immediate cross-repo primitives on top of it: a **repo registry** (`bp3 repo add|list|remove`, auto-registered during `bp3 init` / `bp3 skills install` / `bp3 init-repo`) tracking every local repo (`bp3`, `predictor`, `esc2`/`esc3`, …) and an atomic **cross-repo ticket queue** (`bp3 ticket add|list|claim|done|dismiss`) so a session in `predictor` can file a `bp3` bug or feature request without dirtying `~/m/bp3`'s working tree or colliding with an active quest branch. Teach `/warden` and `using-bp3` to route cross-repo tickets through `bp3 ticket`. Companion Quest 2 (`docs/quests/2026-11-23-sqlite-quest-store/QUEST.md`) migrates `refs/heads/bp3/*` and adds `bp3 db backup`.

ELI5
Right now `bp3` only knows about one git repo at a time. When you're building in `predictor` and hit a `bp3` bug, there's nowhere safe to file it without walking into `~/m/bp3` and risking a dirty branch. This quest gives your MacBook one shared local SQLite database (`~/.local/share/bp3/bp3.sqlite`) where all your repos register themselves automatically on `bp3 init` / `bp3 skills install` and file tickets for each other safely, with atomic claims so future subagents can pull tickets without stepping on each other. Existing quest state in git stays 100% untouched until Quest 2.

## Context

Promotes `docs/icebox/2026-11-18-sqlite-store.md` (copied verbatim to [ICEBOX.md](ICEBOX.md) and removed from `docs/icebox/`). `docs/icebox/2026-11-17-tape-scraper-sqlite.md` remains frozen (raw-tape FTS5 mining is not part of this quest).

Owner drivers (2026-11-23 red chair + scoping):
1. **Cross-repo ticket queue on one MacBook:** Multiple local repos (`bp3`, `predictor`, `esc2`/`esc3`, future apps) need a shared queue so feedback in a downstream repo can split cleanly between the app itself and `bp3` control-plane fixes/features.
2. **Single-machine reality:** No cloud runners or remote workers — everything runs locally on macOS (phone access via Antigravity / Claude / Codex remote control). Apple's `libsqlite3.dylib` lives in the macOS dyld shared cache alongside `libSystem.B.dylib`, removing cross-host packaging friction.
3. **Future subagent trees:** Preparing an ACID WAL primitive (`BEGIN IMMEDIATE`) so future `pi` / `agy` subagent-tree experiments can claim work atomically — without pre-building speculative subagent tables before a spike proves what they need (Gall's law, `CONTEXT.md:80`).
4. **Two-quest split settled by owner (2026-11-23):** `"yeah i like this -> we should break this up into two quests"`, `"yep i like bp3 db backup -> that should be the 2nd quest?"`, `"yep, lgtm, lets /quest both"`.

Measured ground (read 2026-11-23, refreshed 2026-11-24 after `v0.3.0`):

| Fact | Source |
|---|---|
| `CONSTRAINTS.md:21` lists OCaml libs `stdlib unix str yojson ounit2 qcheck-core qcheck-ounit`; `sqlite3` is not yet listed and `opam list --installed` has no sqlite package | `CONSTRAINTS.md:21`, `opam list` |
| `_build/default/src/quest/main.exe` links only `/usr/lib/libSystem.B.dylib`; macOS ships `/usr/bin/sqlite3` 3.54.0 and `libsqlite3.dylib` in the dyld shared cache | `otool -L`, `sqlite3 --version` |
| Local `refs/heads/bp3/*` count = 195 vs `origin/bp3/*` = 3 (192 never pushed to remote) | `git for-each-ref`, `git branch -r` |
| `bin/bp3` dispatches top-level doors (`q`, `n`, `e`, `warden`, `release`, `harness`, `config`, `worktree`, `init-repo`, `init`, `skills`); `db`, `repo`, `ticket` do not exist today | `bin/bp3`, `src/quest/main.ml:750-795` |
| `Store.reserved_slugs` (`src/quest/store.ml:18-24`) guards door/verb spellings against quest/node slug collisions; `db`, `repo`, `ticket` must be reserved | `src/quest/store.ml:18-24` |

## Terms

| Term | Meaning |
|---|---|
| `BP3_DB` | env var overriding the SQLite DB path (mandatory for test isolation so tests never touch the user's real DB); default `$XDG_DATA_HOME/bp3/bp3.sqlite` else `$HOME/.local/share/bp3/bp3.sqlite` |
| `bp3.sqlite` | single machine-local SQLite database in WAL mode (`journal_mode=WAL`, `busy_timeout=5000`, `foreign_keys=ON`), versioned by `PRAGMA user_version` |
| `db` door | top-level CLI door `bp3 db info [--format json\|table]` and `bp3 db -h`; reports resolved DB path, schema version, journal mode, and table row counts |
| `repo` door | top-level CLI door `bp3 repo add [<path>] [--name <slug>]`, `bp3 repo list [--format json\|table]`, `bp3 repo remove <name>` managing the `repos` table (also auto-registered by `bp3 init` / `bp3 skills install` / `bp3 init-repo`) |
| `repo_name` | unique kebab-case slug identifying a local git repo on this MacBook (default: lowercased basename of canonical `Unix.realpath` toplevel, e.g. `bp3`, `predictor`, `esc3`) |
| `ticket` door | top-level CLI door `bp3 ticket add\|list\|read\|claim\|unclaim\|done\|dismiss` managing the cross-repo `tickets` queue |
| `ticket_status` | lifecycle of a ticket: `open \| claimed \| done \| dismissed` (`open <-> claimed` via `claim`/`unclaim`, then terminal `done\|dismissed` from `open` or `claimed`) |
| `ticket_kind` | category of a ticket: `bug \| feature \| note` (default `note`) |
| `E_ALREADY_CLAIMED` | typed refusal (exit 1) when `bp3 ticket claim <id>` loses a race or targets a ticket not in `open` state, carrying `{id, status, claimed_by}` |
| `E_DB_ERROR` | typed refusal (exit 1) on SQLite open/migration/query failure, carrying `{detail}` |

## Inputs

| Input | Source |
|---|---|
| `BP3_DB` | env var; wins over default `$XDG_DATA_HOME/bp3/bp3.sqlite` / `$HOME/.local/share/bp3/bp3.sqlite`; empty counts as unset |
| `BP3_ROOT` / cwd git toplevel | inferred source repo (`--from`) when omitted on `bp3 ticket add` and target path when omitted on `bp3 repo add` |
| `bp3 db info [--format json\|table]` | CLI flags |
| `bp3 repo add [<path>] [--name <slug>]`, `list [--format json\|table]`, `remove <name>` | CLI args/flags (plus auto-called on `bp3 init` / `bp3 skills install` / `bp3 init-repo`) |
| `bp3 ticket add --to <repo> [--from <repo>] [--kind bug\|feature\|note] --title <text> [--body <text>]` | CLI flags; `--to` (must exist in `repos`, else `E_NOT_FOUND` with `facts.registered`) and `--title` required |
| `bp3 ticket list [--to <repo>] [--from <repo>] [--status open\|claimed\|done\|dismissed\|all] [--format json\|table]` | CLI flags; default `--status open` |
| `bp3 ticket read <id> [--format json\|table]` | CLI positional `<id>` + optional `--format`; full ticket including `body` |
| `bp3 ticket claim <id> [--by <owner>]`, `unclaim <id> --reason <text>` | CLI args/flags; default `--by` from `BP3_RUN_ID` else `BP3_HARNESS` else `human`; `unclaim` moves `claimed -> open` and requires `--reason` |
| `bp3 ticket done <id> --reason <text>`, `bp3 ticket dismiss <id> --reason <text>` | CLI args/flags; `--reason` required |

## Outputs

| Output | Shape |
|---|---|
| `bp3.sqlite` schema v1 | tables `repos(name PK, root_path UNIQUE, added_at, last_seen_at)` and `tickets(id INTEGER PK AUTOINCREMENT, from_repo, to_repo, kind, title, body, status, claimed_by, claimed_at, resolved_at, resolution_reason, created_at)` + index `idx_tickets_to_status(to_repo, status)` |
| `bp3 db info` (JSON) | `{"ok":true,"db_path":"...","schema_version":1,"journal_mode":"wal","counts":{"repos":N,"tickets_open":M,"tickets_total":T}}` |
| `bp3 repo ...` (JSON) | `add`: `{"ok":true,"repo":{"name","root_path","added_at"}}`; `list`: `{"ok":true,"repos":[...]}`; `remove`: `{"ok":true,"removed":"<name>"}` |
| `bp3 ticket ...` (JSON) | `add`/`read`: `{"ok":true,"ticket":{id,from_repo,to_repo,kind,title,body,status,claimed_by,claimed_at,resolved_at,resolution_reason,created_at}}`; `list`: `{"ok":true,"tickets":[...]}`; `claim`: `{"ok":true,"ticket":{...,status:"claimed",claimed_by,claimed_at}}` or exit 1 `E_ALREADY_CLAIMED`; `unclaim`: `{"ok":true,"ticket":{...,status:"open",claimed_by:null,claimed_at:null}}`; `done`/`dismiss`: `{"ok":true,"ticket":{...,status,resolved_at,resolution_reason}}` |
| `--format table` | aligned ASCII tables for `db info`, `repo list`, `ticket list` (compact rows), and `ticket read` (full metadata + `body`) |
| `skills/warden/SKILL.md` + `skills/using-bp3/SKILL.md` | host-repo `/warden` instructions to route `bp3` bugs/requests via `bp3 ticket add --to bp3` and check `bp3 ticket list --to <this-repo>` |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 db info
usage: bp3 init ... (unknown door: db)
$ ./bin/bp3 repo list
usage: bp3 init ... (unknown door: repo)
$ ./bin/bp3 ticket list
usage: bp3 init ... (unknown door: ticket)
$ grep sqlite3 CONSTRAINTS.md
(no match)
```

Design trace (after quest lands):

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 db info
  -> ok:true, schema_version:1, journal_mode:"wal", counts:{repos:0,tickets_open:0,tickets_total:0}

$ (cd /path/to/predictor && bp3 init)
  -> installs skills AND auto-registers predictor in repos
$ ./bin/bp3 repo list --format table
  -> lists predictor with canonical path

$ ./bin/bp3 ticket add --from predictor --to bp3 --kind bug \
    --title "brief omits GRADING.md in host desk" \
    --body "repro in predictor quest-1"
  -> ok:true, ticket.id=1, status:"open"

$ ./bin/bp3 ticket list --to bp3
  -> returns [ticket 1]; working tree of bp3 untouched

$ ./bin/bp3 ticket claim 1 --by worker-a
  -> ok:true, status:"claimed", claimed_by:"worker-a"
$ ./bin/bp3 ticket claim 1 --by worker-b
  -> rc 1, error.code:"E_ALREADY_CLAIMED", facts:{id:1,status:"claimed",claimed_by:"worker-a"}

$ ./bin/bp3 ticket done 1 --reason "fixed in commit abc1234"
  -> ok:true, status:"done", resolution_reason:"fixed in commit abc1234"
$ ./bin/bp3 ticket list --to bp3
  -> returns [] (default filters --status open)

$ make check-full
  -> rc 0 (existing refs/heads/bp3/* tests untouched and green; check-constraints green)
```

## Goal and why

Give `bp3` a real local SQLite foundation (`bp3.sqlite`) and solve the immediate multi-repo pain on a single MacBook: working across `bp3`, `predictor`, `esc2`/`esc3`, and future apps without dirtying one repo's working tree when another repo discovers a bug or feature request for it. Proving `sqlite3-ocaml`, WAL concurrency, and `PRAGMA user_version` migrations on additive tables first keeps Quest 1 zero-breakage and de-risks Quest 2's full ledger migration.

## Success picture

- `CONSTRAINTS.md` records the owner's sign-off for OCaml `sqlite3` and the `bp3 db`/`repo`/`ticket` CLI surfaces; `scripts/check-constraints` passes.
- `bp3-q` compiles with `sqlite3` (linking only system `libSystem.B.dylib` + `libsqlite3.dylib` on macOS, zero Homebrew runtime dep) and initializes `~/.local/share/bp3/bp3.sqlite` cleanly on first use with WAL + `busy_timeout = 5000` + `PRAGMA user_version = 1`.
- Any repo on the MacBook registers automatically on `bp3 init` / `bp3 skills install` / `bp3 init-repo` (plus explicit `bp3 repo add|list|remove`) and can file/list/atomically-claim/resolve cross-repo tickets via `bp3 ticket` with typed JSON verdicts and `--format table` views.
- Concurrent `bp3 ticket claim <id>` stress test proves exactly one claimant succeeds and all others receive `E_ALREADY_CLAIMED` (zero SQLite `SQLITE_BUSY` crashes).
- `/warden` and `using-bp3` document cross-repo tickets so downstream repos like `predictor` route `bp3` bugs straight into `bp3 ticket add --to bp3`, rendered across all harnesses.
- Zero regressions to `bp3 q`, `bp3 metrics`, `bp3 warden`, `bp3 release`, or any existing `refs/heads/bp3/*` suite.

## Scope

| In | Out |
|---|---|
| `CONSTRAINTS.md` sign-off + opam `sqlite3` binding + `src/db/dune` (`bp3_db`) + `src/db/db.ml` (WAL, `busy_timeout`, `PRAGMA user_version` v1) | Migrating `refs/heads/bp3/*`, `.git/bp3/`, or `.bp3/desks/` into SQLite (Quest 2: `2026-11-23-sqlite-quest-store`) |
| `bp3 db info`, `bp3 repo add\|list\|remove` (+ auto-register on `bp3 init` / `bp3 skills install` / `bp3 init-repo`), `bp3 ticket add\|list\|claim\|done\|dismiss` + `-h` help + `Store.reserved_slugs` | `bp3 db backup` / `bp3 db check` / iCloud or Google Drive snapshot copy (Quest 2, when SQLite becomes quest truth) |
| Unit tests (`test_db.ml`, `test_ticket.ml`) + fixture & concurrent-claim tests (`test/repo.sh`, `test/ticket.sh`) using `BP3_DB` temp isolation | Subagent tree / blackboard tables (deferred until a `pi`/`agy` subagent-tree spike settles the real schema) |
| Skill updates (`skills/warden/SKILL.md`, `skills/using-bp3/SKILL.md`, renders, `AGENTS.md`/`CLAUDE.md`) as dedicated `skills.1` node | Raw tape FTS5 miner (`docs/icebox/2026-11-17-tape-scraper-sqlite.md`, stays frozen) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):**
  - Adds `sqlite3` to `lang ocaml ... libs` (`CONSTRAINTS.md:21`) and `bp3 db`, `bp3 repo`, `bp3 ticket` to the `bp3 CLI` row in Surfaces (`CONSTRAINTS.md:49`).
  - `/teach` pitch delivered 2026-11-23 (before/change/after, cost of 1 opam dep + macOS system `libsqlite3.dylib`, boring alternatives of plain JSON files in `~/.local/share/bp3/inbox/` or shelling out to `/usr/bin/sqlite3`).
  - Owner words recorded 2026-11-23 / 2026-11-24: `"yep, lgtm, lets /quest both"` (`sqlite3` lib + 2-quest split), `"i'm leaning towards 2, but i don't want to call the repos, i want bp3 install to do it"` (`bp3 db`, `bp3 repo`), and `"im leaning towards ticket"` / `"ticket is good"` (`bp3 ticket`). `db.1` adds the dated Sign-off log row quoting those exact words alongside editing `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Databases earn their keep with concurrent writers and cross-repo coordination (`CONTEXT.md:33`: Invoker runs SQLite; Beads moved off JSONL). Here single-MacBook cross-repo tickets + atomic `BEGIN IMMEDIATE` claims justify WAL SQLite with **no daemon** (`CONTEXT.md:34`).
  - Gall's law (`CONTEXT.md:80`): ship small additive tables first (`repos`, `tickets`) instead of a big-bang rewrite or speculative subagent tables.

## Human touchpoints

| When | Owner |
|---|---|
| Approve frame (or settle any red-ink tweaks on CLI verbs / schema) | owner |
| Promotion (`goal_fin`) | owner |

## Nodes

### Milestone: db

| Node | TL;DR |
|---|---|
| [db.1 - sqlite-foundation](nodes/node-db-1-sqlite-foundation/NODE.md) | `CONSTRAINTS.md` sign-off + opam `sqlite3` dep + `src/db/` (`bp3_db`: `dune`, `db.ml`, `db_cli.ml` — bottom-layer lib, zero dep on `bp3_quest`) + `bp3 db info` + `run_suites.ml` per-suite temp `BP3_DB` isolation + `test/unit/test_db.ml` |

### Milestone: repo

| Node | TL;DR |
|---|---|
| [repo.1 - repo-registry](nodes/node-repo-1-repo-registry/NODE.md) | `src/repo/` (`bp3_repo`: `dune`, `repo_store.ml`, `repo_cli.ml`) + `bp3 repo add\|list\|remove` (canonical realpath identity, `--format json\|table`) + auto-register target repo during `bp3 init` / `bp3 skills install` / `bp3 init-repo` + `test/repo.sh` |

### Milestone: compat (closing red-chair concern)

| Node | TL;DR |
|---|---|
| [compat.1 - install-hook-and-test-isolation](nodes/node-compat-1-install-hook-and-test-isolation/NODE.md) | harden fail-fast `skills_install()` against `test/skills.sh`'s `"project with spaces"` dir name and stale `bp3-q` on `PATH` (`BP3_Q_BIN` + standalone temp `BP3_DB` in `test/skills.sh` & `test/mode.sh`), and assert `src/{db,repo}/dune` have zero dep on `bp3_quest` |

### Milestone: ticket

| Node | TL;DR |
|---|---|
| [ticket.1 - cross-repo-ticket-queue](nodes/node-ticket-1-cross-repo-ticket-queue/NODE.md) | `src/ticket/` (`bp3_ticket`: `dune`, `ticket_store.ml`, `ticket_cli.ml`) + `bp3 ticket add\|list\|read\|claim\|unclaim\|done\|dismiss` (atomic `BEGIN IMMEDIATE` claim with `E_ALREADY_CLAIMED`, `--to`/`--from`/`--kind`/`--status`/`--format`) + concurrent-claim fixture `test/ticket.sh` + `test/unit/test_ticket.ml` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - cross-repo-ticket-skills](nodes/node-skills-1-cross-repo-ticket-skills/NODE.md) | update `skills/warden/SKILL.md` (host-mode `/warden` files `bp3` bugs via `bp3 ticket add --to bp3`), `skills/using-bp3/SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `completions/_bp3`; re-render all harnesses + `test/skills.sh` |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| macOS binary linking | only `libSystem.B.dylib` + system `libsqlite3.dylib` (zero Homebrew runtime dylibs) | `otool -L _build/default/src/quest/main.exe` |
| concurrent claim safety | 10 parallel `bp3 ticket claim <id>` processes -> exactly 1 `ok:true`, 9 `E_ALREADY_CLAIMED`, 0 `E_DB_ERROR` | `test/ticket.sh` |
| `bp3 ticket list` latency | `< 50ms` warm on 100 tickets | timed run |
| regression check | 100% of existing `make check-full` suites green untouched | `make check-full` |

## Risks and red chair

- **Strongest attack (tests polluting real `~/.local/share/bp3/bp3.sqlite`):** "Running `make check-full` or parallel `run-suites` without isolating the DB path will scribble test tickets into the owner's real MacBook database."
  - **Settled in design:** `db.1` implements `BP3_DB` override, and `test/repo.sh` / `test/ticket.sh` / OCaml unit tests always point `BP3_DB` at a fresh temp file (never `$HOME`). `db.1` also checks `XDG_DATA_HOME` before `$HOME/.local/share` so sandboxed callers stay isolated automatically.
- **Second attack (opam `sqlite3` build snag with macOS SDK):** "Recall `Makefile:3-6` pins `MacOSX26.5.sdk` because `MacOSX27.2.sdk` has a broken `libpthread.tbd`. Installing `opam install sqlite3` could trip on the same SDK or link Homebrew's sqlite instead of Apple's."
  - **Settled in design:** `db.1` acceptance gate explicitly verifies `SDKROOT` build via `make check` AND checks `otool -L _build/default/src/quest/main.exe` to confirm no accidental `/opt/homebrew/` dylib coupling (or documents exact build env if pkg-config needs flags).
- **Attack on source (`ICEBOX.md` + owner prompt):**
  - *Icebox assumption rejected:* `ICEBOX.md` proposed `.git/bp3/bp3.sqlite` per-repo to fix JSON races in `.git/bp3/` and speed up `bp3 g r`. Rejected with live evidence: `.git/bp3/` hasn't had a write since Nov 18 and `codebase-diet` is deleting `harness.ml`. The real trigger is a **machine-local cross-repo DB** (`~/.local/share/bp3/bp3.sqlite`), so `bp3.sqlite` lives in `$XDG_DATA_HOME/bp3/`, not `.git/bp3/`.
  - *Premature subagent tables rejected:* Owner wants to explore `pi`/`agy` subagent trees, but designing subagent tables before spiking context-sharing risks another unused `harness.ml` (Gall's law). Settled by omitting subagent tables from Quest 1 and keeping schema v1 minimal (`repos` + `tickets`).

## Open questions

_(None currently open.)_

## Settled in red-ink

- **Round 1 (Shape — owner call: Option 2 + auto-register on install):** Keep all 3 top-level doors (`bp3 db`, `bp3 repo`, `bp3 ticket`), and wire `bp3 init` / `bp3 skills install` (plus `bp3 init-repo`) to automatically register the target repo into `repos` in `bp3.sqlite` so the owner never has to call `bp3 repo add` manually per repo (`bp3 repo add|list|remove` remains for explicit inspection, aliasing, and removal).
- **Round 2 (Output — owner calls: `drop` -> `ticket`, Option 1 `read` + `list`):** Renamed `drop` / `drops` / `drop_store.ml` / `drop.1` across the working copy to `ticket` / `tickets` / `ticket_store.ml` / `ticket.1` (matching `NODE.md` folder/file renames and Quest 2 sync owed at adoption). Locked the 3-door Output contract: `bp3 db info`, `bp3 repo add|list|remove`, `bp3 ticket add|list|read|claim|done|dismiss` (where `read <id>` matches every write's `{"ok":true,"ticket":{...}}` verdict and `--format table` prints full metadata + `body`), exit codes `0 / 1 / 2`, and typed error codes (`E_ALREADY_CLAIMED`, `E_ILLEGAL_EDGE`, `E_EXISTS`, `E_DB_ERROR`, `E_NOT_FOUND`, `E_USAGE`).
- **Round 3 (Inputs — owner call: Option 1 strict `--to`):** `bp3 ticket add --to <repo>` requires `--to` to exist in `repos`; unregistered slugs refuse with `E_NOT_FOUND` (exit `2`) carrying `facts: {"repo": "<slug>", "registered": [...]}` so typos never create orphaned tickets. (Resolves former Open question 1.)
- **Round 4 (Data — owner call: Option 1 minimal schema v1, app-level `--to` check):** Locked schema v1 (`PRAGMA user_version = 1`): `repos(name PK, root_path UNIQUE, added_at, last_seen_at)` and `tickets(id PK AUTOINCREMENT, from_repo, to_repo, kind, title, body, status, claimed_by, claimed_at, resolved_at, resolution_reason, created_at)` + `idx_tickets_to_status(to_repo, status)`. No SQL `FOREIGN KEY` on `tickets.to_repo` (validated in OCaml inside `BEGIN IMMEDIATE` on `add`, so `bp3 repo remove` preserves historical tickets); no extra `source_*` provenance columns.
- **Round 5 (State — owner call: Option 1 `unclaim`, terminal `done`/`dismissed`):** Added `bp3 ticket unclaim <id> --reason <text>` moving `claimed -> open` (clearing `claimed_by`/`claimed_at`; refusing non-`claimed` with `E_ILLEGAL_EDGE`) so crashed subagents or accidental claims never leave a ticket stuck, while keeping `done` and `dismissed` terminal. (Resolves former Open question 2.)
- **Round 6 (Functions — owner calls: `src/{db,repo,ticket}/` + Option 2 fail-fast hook + `run_suites` `BP3_DB` isolation):** Each new door owns its own top-level dune library under `src/`: `src/db/` (`bp3_db`: `db.ml`, `db_cli.ml`), `src/repo/` (`bp3_repo`: `repo_store.ml`, `repo_cli.ml`, depends on `bp3_db`), and `src/ticket/` (`bp3_ticket`: `ticket_store.ml`, `ticket_cli.ml`, depends on `bp3_db`, `bp3_repo`). Zero new business logic or flag parsers go into `src/quest/` — `src/quest/main.ml` only adds 3 one-line dispatch arms (`db`, `repo`, `ticket`). Splitting the existing 23 files in `src/quest/` is deferred to [docs/icebox/2026-11-24-split-src-quest.md](../../icebox/2026-11-24-split-src-quest.md). In `bin/bp3` `skills_install()`, auto-registration (`repo add "$target"`) **fails fast** (exits non-zero on error whenever the engine binary exists and `$target` is a git repo), and `run_suites.ml` (plus `test/skills.sh`/`test/mode.sh`) isolates a fresh temp `BP3_DB` per run so tests never touch `~/.local/share/bp3/bp3.sqlite`.
- **Round 7 (Names & Concepts — owner call: Option 1):** Locked the complete identifier & concept table (`db`, `repo`, `ticket`, `repos`, `tickets`, `src/{db,repo,ticket}/`, `BP3_DB`, `E_ALREADY_CLAIMED`, `E_DB_ERROR`) and reused `E_ILLEGAL_EDGE` with ticket-native facts `{"id", "status", "verb", "legal_verbs"}` for illegal ticket transitions.
- **Round 8 (Plan — owner call: Option 1 settle):** Locked the sequential node railway (`db.1 -> repo.1 -> ticket.1 -> skills.1`, plus closing red-chair concern node `compat.1` after `repo.1`), with Known + QCheck2 property test splits per node and Quest-level functional tests. Ready for adoption.

## Quest-level functional tests

1. **Happy path — cross-repo lifecycle across two repos (functional fixture, `test/ticket.sh`):**
   - *Start:* Fresh temp `BP3_DB` + two temp git repos (`fake-bp3`, `fake-predictor`).
   - *Action:* Run `bp3 init` in `fake-bp3` and `fake-predictor` (verifying both auto-register); from `fake-predictor`, file `bp3 ticket add --to fake-bp3 --kind bug --title "..." --body "line1\nline2"`; from `fake-bp3`, run `bp3 ticket list --to fake-bp3 --format table`, `bp3 ticket read 1 --format table`, `bp3 ticket claim 1 --by worker-a`, `bp3 ticket unclaim 1 --reason "handoff"`, `bp3 ticket claim 1 --by worker-b`, `bp3 ticket done 1 --reason "fixed"`, and `bp3 db info`.
   - *Result:* Every command exits `0`; `fake-bp3` has `git status --porcelain` empty and `0` new `refs/heads/bp3/*` refs; `bp3 db info` reports `repos: 2, tickets_open: 0, tickets_total: 1`.
2. **Refusal & race path — state unchanged (functional fixture, `test/ticket.sh`):**
   - *Start:* Temp `BP3_DB` with `fake-bp3` registered and open ticket `#1`.
   - *Action:* (a) `bp3 ticket add --to nonexistent --title "x"`; (b) spawn 10 concurrent `bp3 ticket claim 1` processes; (c) attempt `bp3 ticket done 1 --reason "x"` twice.
   - *Result:* (a) exits `2` (`E_NOT_FOUND`, `facts.registered: ["fake-bp3"]`), ticket count unchanged; (b) exactly 1 exit `0` + 9 exit `1` (`E_ALREADY_CLAIMED`), 0 `E_DB_ERROR`; (c) second `done` exits `1` (`E_ILLEGAL_EDGE`, `facts: {id:1, status:"done", verb:"done", legal_verbs:[]}`), row unchanged.
3. **Crash / restart persistence & cross-surface consistency (functional fixture, `test/ticket.sh`):**
   - *Start:* Fresh process after writes above (no long-lived daemon).
   - *Action:* Read via `bp3 ticket read 1`, `bp3 ticket list --status all`, `bp3 ticket list --status all --format table`, and `bp3 db info` in separate subprocesses.
   - *Result:* All surfaces agree identically on `id`, `status`, `claimed_by`, `resolution_reason`, and counts; `~/.local/share/bp3/bp3.sqlite` untouched.
4. **True end-to-end check (manual / post-install smoke, labeled `design trace`):** After `make install` in `bp3`, run `bp3 init` inside real `~/m/bp3` and `~/m/predictor`, file and resolve one real ticket across repos, and verify `otool -L ~/.local/bin/bp3-q` links only `libSystem.B.dylib` + system `libsqlite3.dylib`.

## Node diagram

```text
db.1 (CONSTRAINTS + opam sqlite3 + src/db/ bp3_db + bp3 db info + run_suites BP3_DB)
   ──► repo.1 (src/repo/ bp3_repo + bp3 repo + fail-fast auto-register on bp3 init/skills install/init-repo)
   ──► compat.1 (closing red-chair concern: "project with spaces" + stale PATH bp3-q + standalone test DB isolation)
   ──► ticket.1 (src/ticket/ bp3_ticket + bp3 ticket + strict --to + unclaim + atomic WAL race test)
   ──► skills.1 (warden + using-bp3 + AGENTS/CLAUDE + completions + renders)
```
