# LOG — 2026-11-23-sqlite-control-plane

Living run log for `2026-11-23-sqlite-control-plane` (`induct-inline-yolo` in quest desk `.bp3/worktrees/2026-11-23-sqlite-control-plane`).

## Nodes

| Node | Status | Cycles | Commit | Notes |
|---|---|---|---|---|
| `node-db-1-sqlite-foundation` | landed (`node_fin`) | 1 | `09a84cd` | `CONSTRAINTS.md` sign-off + `src/db/` (`bp3_db`) + `bp3 db info` + `Suites.suite_env` `BP3_DB` isolation + `test_db.ml` (Known + QCheck2); `otool -L` links only `/usr/lib/libsqlite3.dylib` + `libSystem.B.dylib`; check-full 34/34 |
| `node-repo-1-repo-registry` | landed (`node_fin`) | 2 | `6705016` | `src/repo/` (`bp3_repo`) + `bp3 repo add\|list\|remove` + fail-fast auto-register on `bp3 init` / `skills install` / `init-repo` + `test_repo.ml` (Known + QCheck2) + `test/repo.sh`; c1 caught `bin/bp3` `run_q()` overwriting `BP3_ROOT` for `repo` door, fixed in c2; check-full 35/35 |
| `node-compat-1-install-hook-and-test-isolation` | landed (`node_fin`) | 1 | `a5f363d` | Isolated `BP3_DB` and `BP3_Q_BIN` defaults in `test/skills.sh` and `test/mode.sh` (passes under stale `PATH` `bp3-q` without touching `~/.local/share/bp3/bp3.sqlite`); pinned `"project with spaces"` -> `"project-with-spaces"` regression in `test_repo.ml` and `test/skills.sh`; check-full 35/35 |
| `node-ticket-1-cross-repo-ticket-queue` | landed (`node_fin`) | 1 | `e3ccd5f` | `src/ticket/` (`bp3_ticket`, zero `bp3_quest` dep) + `bp3 ticket add\|list\|read\|claim\|unclaim\|done\|dismiss` + strict `--to` validation + atomic `BEGIN IMMEDIATE` claim/unclaim/resolve + `test_ticket.ml` (Known + QCheck2 state-machine) + `test/ticket.sh` (all 3 Quest-level fixtures incl. 10-way concurrent claim race: 1 ok, 9 `E_ALREADY_CLAIMED`, 0 `E_DB_ERROR`); check-full 36/36 |
| `node-skills-1-cross-repo-ticket-skills` | landed (`node_fin`) | 1 | `fb317fd` | Updated `skills/warden/SKILL.md` (host `bp3 ticket add --to bp3`, self `bp3 ticket list --to bp3`), `skills/using-bp3/SKILL.md`, synced `AGENTS.md`/`CLAUDE.md`, added `db`/`repo`/`ticket` to `completions/_bp3` + `completions/bp3.bash`, re-rendered `.claude`/`.pi`/`.agents`, pinned assertions in `test/skills.sh` + `test/completion.sh`; check-full 36/36 |

## Build notes & decisions

- **2026-11-24:** Activated quest on `quest/2026-11-23-sqlite-control-plane` in quest desk (`58dd3d3`); verified `sqlite3 5.4.1` is already installed in the local opam switch and links only macOS system `/usr/lib/libsqlite3.dylib`.
- **OUnit2 env-leak prevention (`db.1`, `repo.1`, `ticket.1`):** Added optional `?db_path` parameter to `Db_cli.run`, `Repo_cli.run`, and `Ticket_cli.run` so unit tests pass isolated paths without mutating `BP3_DB` via `Unix.putenv`.
- **`bin/bp3` `run_q()` caller cwd preservation (`repo.1` c2):** `db`, `repo`, and `ticket` doors skip `BP3_ROOT="$root"` override so `bp3 repo add` and `bp3 ticket add` resolve the caller's cwd repo rather than `bp3`'s own checkout.
- **Lock-free git root lookup (`ticket.1`):** `Ticket_store.add` resolves caller git root via `Repo_store.resolve_main_root` before opening `BEGIN IMMEDIATE`, avoiding holding SQLite's write lock across a `git` subprocess.
- **Non-blocking grader follow-ups logged for post-land `/warden`:**
  - `repo.1` c2: `src/repo/repo_store.ml:104-113` runs `Db.slugify` before checking `(None, find_by_path_in db root_path)` (punctuation-only dir name previously registered with custom `--name` would fail `--name`-less refresh).
  - `compat.1` c1: `test/skills.sh` sets `BP3_COMPLETIONS_DIR` only for `agy` sub-cases rather than globally at file top like `test/mode.sh`.
  - `ticket.1` c1: `src/ticket/ticket_cli.ml` uses `List.exists is_help rest` on subcommand args (same convention as `repo_cli.ml`).
  - `skills.1` c1: `completions/_bp3` and `completions/bp3.bash` intercept `--*` early with `_bp3_flags` (same pre-existing behavior as `warden`, `release`, `config`); `skills/warden/SKILL.md` line 107 omits `--reason` shorthand on `unclaim|done|dismiss`.
