---
date: 2026-11-23
quest: ../../QUEST.md
node: db.1
status: proposed
---

# db.1 - sqlite-foundation: OCaml sqlite3 dep, src/db/ (bp3_db) WAL store, bp3 db info, and run_suites BP3_DB isolation

## TL;DR

Add `sqlite3` (OCaml `libs`) and `bp3 db`, `bp3 repo`, `bp3 ticket` (`bp3 CLI` surfaces) to `CONSTRAINTS.md` with the owner's dated Sign-off log row; build the standalone bottom-layer dune library `src/db/` (`bp3_db`: `dune`, `db.ml`, `db_cli.ml`, depending only on `sqlite3 yojson unix` — **zero dependency on `bp3_quest`**) opening `$BP3_DB` (else `$XDG_DATA_HOME/bp3/bp3.sqlite`, else `$HOME/.local/share/bp3/bp3.sqlite`) in WAL mode with `busy_timeout = 5000`, `foreign_keys = ON`, and `PRAGMA user_version = 1` (`repos`, `tickets`, `idx_tickets_to_status`); include shared `Db.verdict_err`, `Db.valid_slug`, `Db.slugify`, and `Db.now_ts` helpers so `bp3_repo` and `bp3_ticket` stay decoupled from `bp3_quest`; wire `bp3 db info [--format json|table]` via a one-line dispatch in `main.ml` + `bin/bp3`; reserve `db`/`repo`/`ticket` in `Store.reserved_slugs`; and inject a fresh per-suite temp `BP3_DB` in `src/quest/run_suites.ml` so no suite can pollute `~/.local/share/bp3/bp3.sqlite`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 db info
usage: bp3 init ...
$ grep sqlite3 CONSTRAINTS.md
(no match)
$ ls src/db/
ls: src/db/: No such file or directory
```

Design trace:

```text
$ BP3_DB="$(mktemp -d)/bp3.sqlite" ./bin/bp3 db info
{"ok":true,"db_path":"/var/.../bp3.sqlite","schema_version":1,"journal_mode":"wal","counts":{"repos":0,"tickets_open":0,"tickets_total":0}}
$ BP3_DB="/tmp/test.sqlite" ./bin/bp3 db info --format table
  -> aligned key/value table on stdout, rc 0
$ ./bin/bp3 db -h
  -> prints usage on stdout, rc 0, creates no DB file
$ otool -L _build/default/src/quest/main.exe
  -> links only /usr/lib/libSystem.B.dylib and /usr/lib/libsqlite3.dylib (no /opt/homebrew/)
$ ./scripts/check-constraints && make check-full
  -> rc 0
```

```yaml
objective: wire sqlite3-ocaml into a standalone bottom-layer src/db/ (bp3_db) library with WAL migrations, bp3 db info, and per-suite temp BP3_DB isolation
prove by:
  - ./scripts/check-constraints
  - grep -v bp3_quest src/db/dune (zero upward dependency on bp3_quest)
  - dune test (test/unit/test_db.ml: known cases + QCheck2 resolve_path & slugify properties)
  - otool -L _build/default/src/quest/main.exe (no Homebrew runtime dylibs)
  - BP3_DB=<tmp> ./bin/bp3 db info && ./bin/bp3 db -h
  - make check-full (verifying real ~/.local/share/bp3/bp3.sqlite is untouched)
done when: check-constraints passes with owner sign-off row, bp3 db info returns schema_version 1 in WAL mode, and make check-full is green
```

## Diagram

```text
BP3_DB (env) ──(else)──► $XDG_DATA_HOME/bp3/bp3.sqlite ──(else)──► $HOME/.local/share/bp3/bp3.sqlite
                                          │
                                          ▼
                             src/db/ (bp3_db: sqlite3 yojson unix)
                               ├── Db.with_db: mkdir -p -> WAL / busy_timeout / foreign_keys -> migrate 0->1
                               ├── Db.with_tx_immediate: BEGIN IMMEDIATE ... COMMIT / ROLLBACK
                               ├── Db.{verdict_ok, verdict_err, valid_slug, slugify, now_ts}
                               └── Db_cli.run : string list -> int  (bp3 db info | -h)
```

## Pseudocode

```python
def resolve_db_path() -> str:
    if env("BP3_DB"):
        return env("BP3_DB")
    base = env("XDG_DATA_HOME") or f"{env('HOME')}/.local/share"
    return f"{base}/bp3/bp3.sqlite"

def open_db(path: str):
    mkdir_p(dirname(path))
    db = sqlite3_open(path)
    exec(db, "PRAGMA journal_mode=WAL;")
    exec(db, "PRAGMA busy_timeout=5000;")
    exec(db, "PRAGMA foreign_keys=ON;")
    migrate(db)
    return db

def migrate(db):
    with tx_immediate(db):
        ver = query_int(db, "PRAGMA user_version;")
        if ver == 0:
            exec(db, SCHEMA_V1_DDL)   # repos, tickets, idx_tickets_to_status
            exec(db, "PRAGMA user_version = 1;")
        elif ver > CURRENT_VERSION:
            raise E_DB_ERROR(f"DB schema v{ver} is newer than this bp3 (v{CURRENT_VERSION})")
```

## Tables

| Field | Value |
|---|---|
| Intent | establish standalone bottom-layer `src/db/` (`bp3_db`), `CONSTRAINTS.md` sign-off, `bp3 db info`, and `run_suites.ml` `BP3_DB` isolation |
| Lane | standard |
| Output | `CONSTRAINTS.md`, `src/db/{dune,db.ml,db_cli.ml}`, `src/quest/{dune,store.ml,main.ml,run_suites.ml}`, `bin/bp3`, `test/unit/{dune,test_db.ml}` |
| Acceptance | fails today (`bp3 db info` unknown, `sqlite3` unlisted in `CONSTRAINTS.md`, `src/db/` absent); passes when `bp3 db info`, `test_db.ml`, `check-constraints`, and `make check-full` pass |
| Depends on | none |
| Must not touch | `refs/heads/bp3/*` storage behavior, `skills/*` |

## Prose

`src/db/` (`bp3_db`) is intentionally a bottom-layer library depending only on `sqlite3 yojson unix` — never on `bp3_quest` — so Quest 2 (`2026-11-23-sqlite-quest-store`) can make `bp3_quest` depend on `bp3_db` with zero circular dependencies. `Db_cli.run` returns an `int` exit code directly after printing JSON/table output, so `main.ml` needs only one line (`| "db" :: rest -> Db_cli.run rest`).

`Db.slugify` normalizes any non-`[a-z0-9]` run (spaces, underscores, dots, slashes) to `-`, lowercases ASCII letters, collapses consecutive `-`, and trims leading/trailing `-` so directory names like `"project with spaces"` become `"project-with-spaces"`.

Edge cases:
- **Forward schema guard:** `PRAGMA user_version > 1` refuses cleanly with `E_DB_ERROR` naming both versions.
- **Concurrent first-open race:** Re-read `PRAGMA user_version` *inside* `BEGIN IMMEDIATE` before running DDL so simultaneous first-run processes never race on `CREATE TABLE`.
- **`bp3 db -h`:** Prints help and returns `0` *before* calling `Db.with_db` so help never creates a DB file.
- **`run_suites.ml` isolation:** If `BP3_DB` is unset in the parent environment, create a temp directory per suite, pass `BP3_DB=<tmp>/bp3.sqlite`, and remove it on suite exit.

## Tests

- **Known cases (`test/unit/test_db.ml`):** fresh DB init (`user_version = 1`, `journal_mode = wal`), idempotent re-open, forward-version `E_DB_ERROR`, unwritable path `E_DB_ERROR`, `bp3 db -h` creates no file, `Db.slugify` goldens (`"My_App"` → `"my-app"`, `"project with spaces"` → `"project-with-spaces"`, `"---"` → `Error`).
- **Property-based (QCheck2 in `test/unit/test_db.ml`):** `Db.resolve_path` obeys strict `BP3_DB > XDG_DATA_HOME > HOME/.local/share` precedence across random non-empty/empty env combinations.
