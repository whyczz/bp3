---
date: 2026-11-23
quest: ../../QUEST.md
node: backup.1
status: proposed
---

# backup.1 - db-backup-and-check: schema v2, VACUUM INTO cloud-safe backup, and integrity check

## TL;DR

Bump `bp3.sqlite` to `PRAGMA user_version = 2` (adding `quests`, `nodes`, `ledger_events`, `metrics`, `desks`, and `kv_config` tables) and ship **`bp3 db backup [--to <dir>] [--keep N]`** + **`bp3 db check`**. `bp3 db backup` creates a single self-contained snapshot via `VACUUM INTO` in a local APFS temp file, verifies `PRAGMA integrity_check` on the snapshot, copies it into `<backup_dir>/bp3-YYYY-MM-DD.sqlite` and `<backup_dir>/bp3-latest.sqlite` (safe for Google Drive, iCloud Drive, or any folder — zero `-wal`/`-shm` sidecars), and prunes daily snapshots beyond `--keep N` (default `14`). Proved by `test/db-backup.sh` and `test/unit/test_db.ml`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 db backup
usage: bp3 init ...
$ ./bin/bp3 db check
usage: bp3 init ...
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ BDIR="$(mktemp -d)"
$ ./bin/bp3 db check
{"ok":true,"db_path":"...","schema_version":2,"integrity":"ok","foreign_keys":"ok",...}
$ ./bin/bp3 db backup --to "$BDIR" --keep 3
{"ok":true,"source":"...","snapshot":".../bp3-2026-11-23.sqlite","latest":".../bp3-latest.sqlite","bytes":...,"integrity":"ok","pruned":[]}
$ ls "$BDIR"
bp3-2026-11-23.sqlite  bp3-latest.sqlite   (zero -wal or -shm files!)
$ sqlite3 "$BDIR/bp3-latest.sqlite" "PRAGMA integrity_check;"
ok
```

```yaml
objective: add schema v2 tables plus cloud-safe VACUUM INTO backups (Google Drive / iCloud Drive / local dir) and DB integrity checks before migrating quest truth
prove by:
  - dune test (test/unit/test_db.ml: v1->v2 idempotent migration, kv_config read/write, snapshot pruning logic, live-DB-inside-cloud-dir warning)
  - test/db-backup.sh (backup to --to dir, BP3_BACKUP_DIR, kv_config backup_dir, missing dir E_BACKUP_CONFIG, zero -wal/-shm sidecars, snapshot readable & integrity ok while WAL active, daily pruning --keep 2, db check on healthy + corrupted file returning E_DB_CORRUPT)
  - make check-full
done when: schema v2 migrates cleanly from v1, bp3 db backup produces verified single-file snapshots with pruning, and make check-full passes
```

## Diagram

```text
Live WAL DB (~/.local/share/bp3/bp3.sqlite + -wal + -shm)
       │
       │ 1. SQL: VACUUM INTO '<local-apfs-tmp>/snap-<pid>.sqlite'
       ▼
Local temp snapshot (single self-contained file, zero sidecars)
       │
       │ 2. Open read-only -> PRAGMA integrity_check == "ok"
       ▼
<backup_dir> (Google Drive / iCloud Drive / local path)
   ├── bp3-YYYY-MM-DD.sqlite   (written via temp+rename inside backup_dir)
   ├── bp3-latest.sqlite       (updated copy; GDrive keeps 30d version history)
   └── prune daily files beyond --keep N (newest N kept)
```

## Pseudocode

```python
def db_backup(db, to_opt, keep=14):
    assert keep >= 1
    dest_dir = to_opt or env("BP3_BACKUP_DIR") or kv_get(db, "backup_dir")
    if not dest_dir:
        raise E_BACKUP_CONFIG("pass --to <dir>, set BP3_BACKUP_DIR, or configure backup_dir")
    mkdir_p(dest_dir)
    tmp_snap = mktemp_local_apfs("bp3-snap.sqlite")   # never inside cloud-sync dir!
    try:
        exec(db, "VACUUM INTO ?;", [tmp_snap])
        assert check_integrity_file(tmp_snap) == "ok"
        today = f"bp3-{utc_date()}.sqlite"
        copy_atomic(tmp_snap, join(dest_dir, today))
        copy_atomic(tmp_snap, join(dest_dir, "bp3-latest.sqlite"))
        pruned = prune_daily_snapshots(dest_dir, keep=keep)
        return ok(snapshot=join(dest_dir, today), latest=join(dest_dir, "bp3-latest.sqlite"),
                  bytes=file_size(tmp_snap), integrity="ok", pruned=pruned)
    finally:
        unlink_if_exists(tmp_snap)
```

## Tables

| Field | Value |
|---|---|
| Intent | establish schema v2 and a verified cloud-safe backup/check safety net before moving quest truth into SQLite |
| Lane | standard |
| Output | `src/quest/db.ml` (schema v2 migration + `backup` + `check`), `src/quest/main.ml`, `bin/bp3`, `test/unit/test_db.ml`, `test/db-backup.sh`, `test/suites.tsv` |
| Acceptance | fails today (`bp3 db backup` / `bp3 db check` unknown); passes when `test/db-backup.sh` and `make check-full` pass |
| Depends on | Quest 1 (`2026-11-23-sqlite-control-plane`) |
| Must not touch | `refs/heads/bp3/*` behavior, `skills/*` |

## Prose

Putting `backup.1` first guarantees that before a single quest ledger moves off git refs, the backup mechanism works end-to-end. Running `VACUUM INTO` into a local APFS temp file (not directly inside `~/Library/CloudStorage/GoogleDrive-...` or `~/Library/Mobile Documents/com~apple~CloudDocs/`) avoids Apple FileProvider partial-sync or locking issues during SQLite page writes.

Edge cases:
- **Existing v1 DB upgrade:** Upgrading a DB created by Quest 1 (`user_version = 1`) with existing `repos` and `drops` rows must preserve every row untouched inside a single `BEGIN IMMEDIATE` migration to `user_version = 2`.
- **Snapshot overwrite on same day:** Running `bp3 db backup` twice on `2026-11-23` cleanly replaces `bp3-2026-11-23.sqlite` and `bp3-latest.sqlite` without leaving temp files behind.
- **Live DB guard:** If `BP3_DB` points inside `CloudDocs` or `CloudStorage`, emit `W_DB_IN_CLOUD_SYNC` warning on `bp3 db info` / `bp3 db check` so nobody accidentally puts the live WAL DB inside iCloud/Google Drive.
- **Pruning safety:** Only delete files matching strict `^bp3-[0-9]{4}-[0-9]{2}-[0-9]{2}\.sqlite$` — never touch `bp3-latest.sqlite` or unrelated files in `backup_dir`.
