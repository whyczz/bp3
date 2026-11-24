---
date: 2026-11-23
quest: ../../QUEST.md
node: db.1
status: proposed
---

# db.1 - sqlite-foundation: OCaml sqlite3 dep, db.ml WAL store, and bp3 db info

## TL;DR

Add `sqlite3` to `CONSTRAINTS.md` (with the owner's 2026-11-23 sign-off row) and `src/quest/dune`, build `src/quest/db.ml` opening `$BP3_DB` (default `$XDG_DATA_HOME/bp3/bp3.sqlite` else `$HOME/.local/share/bp3/bp3.sqlite`) in WAL mode with `busy_timeout = 5000`, `foreign_keys = ON`, and `PRAGMA user_version` schema v1 (`repos` + `drops`), expose `bp3 db info [--format json|table]` through `bin/bp3` and `main.ml`, reserve `db`/`repo`/`drop` in `Store.reserved_slugs`, and prove migrations + WAL settings in `test/unit/test_db.ml`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 db info
usage: bp3 init ...
$ grep sqlite3 CONSTRAINTS.md src/quest/dune
(no matches)
```

Design trace:

```text
$ BP3_DB="$(mktemp -d)/bp3.sqlite" ./bin/bp3 db info
{"ok":true,"db_path":"/var/.../bp3.sqlite","schema_version":1,"journal_mode":"wal","counts":{"repos":0,"drops_open":0,"drops_total":0}}
$ BP3_DB="/tmp/test.sqlite" ./bin/bp3 db info --format table
  -> aligned key/value table on stdout, rc 0
$ ./bin/bp3 db -h
  -> prints usage on stdout, rc 0, creates no DB file
$ otool -L _build/default/src/quest/main.exe
  -> links only /usr/lib/libSystem.B.dylib and /usr/lib/libsqlite3.dylib (no /opt/homebrew/)
$ ./scripts/check-constraints && make check
  -> rc 0
```

```yaml
objective: wire sqlite3-ocaml into bp3-q with a WAL-mode versioned DB module and read-only bp3 db info door
prove by:
  - ./scripts/check-constraints
  - dune test (test/unit/test_db.ml: fresh DB init, idempotent migrate v0->v1, WAL + busy_timeout pragmas, BP3_DB override, E_DB_ERROR on unwritable path)
  - otool -L _build/default/src/quest/main.exe (no Homebrew dylibs)
  - BP3_DB=<tmp> ./bin/bp3 db info && ./bin/bp3 db -h
  - make check-full
done when: check-constraints passes with owner sign-off row, bp3 db info returns schema_version 1 in WAL mode, and all unit/fixture suites pass
```

## Diagram

```text
BP3_DB (env) ──(else)──► $XDG_DATA_HOME/bp3/bp3.sqlite ──(else)──► $HOME/.local/share/bp3/bp3.sqlite
                                          │
                                          ▼
                                  Db.with_db (path)
                                    ├── mkdir -p parent dir
                                    ├── PRAGMA journal_mode = WAL
                                    ├── PRAGMA busy_timeout = 5000
                                    ├── PRAGMA foreign_keys = ON
                                    └── migrate: user_version 0 ──► 1 (repos, drops, idx)
                                          │
                                          ▼
                               bp3 db info [--format json|table]
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
    ver = query_int(db, "PRAGMA user_version;")
    if ver == 0:
        with tx_immediate(db):
            exec(db, SCHEMA_V1_DDL)   # repos, drops, idx_drops_to_status
            exec(db, "PRAGMA user_version = 1;")
    elif ver > CURRENT_VERSION:
        raise E_DB_ERROR(f"DB schema v{ver} is newer than this bp3 (v{CURRENT_VERSION})")
```

## Tables

| Field | Value |
|---|---|
| Intent | establish the single SQLite engine module (`Db`), schema versioning, and `CONSTRAINTS.md` sign-off |
| Lane | standard |
| Output | `CONSTRAINTS.md` (sign-off row + `sqlite3` lib + `db`/`repo`/`drop` surfaces), `src/quest/dune`, `src/quest/db.ml`, `src/quest/store.ml` (`reserved_slugs`), `src/quest/main.ml`, `bin/bp3`, `test/unit/test_db.ml`, `test/unit/dune` |
| Acceptance | fails today (`bp3 db info` returns usage error, `sqlite3` not in `CONSTRAINTS.md`); passes when `bp3 db info` + `test_db.ml` + `make check-full` pass |
| Depends on | none |
| Must not touch | `refs/heads/bp3/*` storage behavior, `skills/*` |

## Prose

`Db.with_db` always closes the SQLite handle via `Fun.protect` so short-lived CLI processes never leak file descriptors or stale WAL locks. `bp3 db -h` must print help **before** calling `Db.with_db` so help never creates a database file on disk.

Edge cases:
- **Forward schema guard:** If an older `bp3-q` opens a DB with `PRAGMA user_version > current_version`, refuse cleanly with `E_DB_ERROR` naming both versions (mirrors `E_VERSION_AHEAD` for ledgers).
- **Concurrent first-open race:** Wrap the `user_version = 0 -> 1` migration inside `BEGIN IMMEDIATE` and re-read `PRAGMA user_version` inside the transaction so two simultaneous first invocations never race on `CREATE TABLE`.
- **macOS SDK / linking:** Verify `opam install sqlite3` builds against Apple's system `libsqlite3` under `Makefile`'s `SDKROOT` rule; do not link Homebrew's sqlite unless explicitly required.
