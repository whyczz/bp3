---
date: 2026-11-23
quest: ../../QUEST.md
node: repo.1
status: proposed
---

# repo.1 - repo-registry: track local repos in bp3.sqlite via bp3 repo

## TL;DR

Add `src/quest/repo_store.ml` and the `bp3 repo` CLI door (`add [<path>] [--name <slug>]`, `list [--format json|table]`, `remove <name>`, `-h`) backed by the `repos` table in `bp3.sqlite`, normalizing every path via `git rev-parse --show-toplevel` + `Unix.realpath` so worktrees and `/var` vs `/private/var` symlinks never register duplicates. Add fixture coverage in `test/repo.sh`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 repo list
usage: bp3 init ...
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 repo add /tmp/fake-predictor --name predictor
{"ok":true,"repo":{"name":"predictor","root_path":"/private/tmp/fake-predictor","added_at":"2026-11-23T..."}}
$ ./bin/bp3 repo add /tmp/fake-predictor --name predictor
  -> idempotent upsert (updates last_seen_at), rc 0
$ ./bin/bp3 repo add /tmp/other-repo --name predictor
  -> rc 1, error.code:"E_EXISTS" (name already bound to different path)
$ ./bin/bp3 repo list --format table
name       root_path                      last_seen_at
predictor  /private/tmp/fake-predictor    2026-11-23T...
$ ./bin/bp3 repo remove predictor
{"ok":true,"removed":"predictor"}
```

```yaml
objective: register, list, and remove local git repos in bp3.sqlite with canonical path deduplication
prove by:
  - test/repo.sh (add explicit path, add cwd default, add from worktree resolves main repo root, duplicate name conflict E_EXISTS, list json & table, remove existing & E_NOT_FOUND)
  - make check-full
done when: test/repo.sh passes in suites.tsv and make check-full is green
```

## Diagram

```text
bp3 repo add [<path>] [--name <slug>]
        │
        ▼
  git -C <path> rev-parse --git-common-dir ──► main repo root (Unix.realpath)
        │                                       (worktrees resolve to main repo!)
        ▼
  default name = valid_slug(lowercase(basename(root)))
        │
        ▼
  repos table (name PK, root_path UNIQUE, added_at, last_seen_at)
```

## Pseudocode

```python
def resolve_main_repo_root(path: str) -> str:
    common = git_out(path, ["rev-parse", "--git-common-dir"])
    if not common:
        raise E_NOT_FOUND("not a git repository")
    abs_common = realpath(join(path, common))
    # <repo>/.git -> <repo>; bare repo keeps abs_common
    return dirname(abs_common) if basename(abs_common) == ".git" else abs_common

def repo_add(db, path_opt, name_opt):
    root = resolve_main_repo_root(path_opt or current_root())
    name = name_opt or slugify(basename(root))
    check_slug(name)
    with tx_immediate(db):
        existing_by_name = find_by_name(db, name)
        if existing_by_name and existing_by_name.root_path != root:
            raise E_EXISTS(f"repo name {name} already points to {existing_by_name.root_path}")
        existing_by_path = find_by_path(db, root)
        if existing_by_path and existing_by_path.name != name:
            raise E_EXISTS(f"repo path {root} already registered as {existing_by_path.name}")
        upsert_repo(db, name, root, now_ts())
```

## Tables

| Field | Value |
|---|---|
| Intent | maintain the MacBook's canonical registry of local git repos in `bp3.sqlite` |
| Lane | standard |
| Output | `src/quest/repo_store.ml`, `src/quest/main.ml`, `bin/bp3`, `test/repo.sh`, `test/suites.tsv` |
| Acceptance | fails today (`bp3 repo` unknown door); passes when `test/repo.sh` and `make check-full` pass |
| Depends on | `db.1 - sqlite-foundation` |
| Must not touch | `refs/heads/bp3/*`, `skills/*` |

## Prose

A desk/worktree inside `predictor` (`../predictor.desks/quest-1`) must resolve to the same `predictor` entry as the main checkout — using `--git-common-dir` + `Unix.realpath` (same pattern as `Metrics_io.main_root` at `src/quest/metrics_io.ml:51-54`) guarantees worktrees never create duplicate repo rows.

Edge cases:
- **Non-git path:** `bp3 repo add /tmp/not-a-repo` refuses cleanly with `E_NOT_FOUND` (exit 2).
- **Name sanitization:** If a directory name has underscores or uppercase (`My_App`), auto-derived name normalizes to kebab-case (`my-app`) and validates via `Store.check_slug`; explicit `--name` is checked strictly without silent mangling.
- **Removing a repo with existing drops:** `repos` is not a hard `ON DELETE CASCADE` parent of `drops` — removing a repo unregisters it from `repos` without wiping historical drop records.
