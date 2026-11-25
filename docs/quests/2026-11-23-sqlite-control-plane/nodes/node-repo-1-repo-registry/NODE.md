---
date: 2026-11-23
quest: ../../QUEST.md
node: repo.1
status: proposed
---

# repo.1 - repo-registry: src/repo/ (bp3_repo), bp3 repo add|list|remove, and fail-fast auto-register on install

## TL;DR

Build `src/repo/` (`bp3_repo`: `dune`, `repo_store.ml`, `repo_cli.ml`, depending only on `bp3_db yojson unix` — zero dep on `bp3_quest`) implementing `bp3 repo add [<path>] [--name <slug>]`, `bp3 repo list [--format json|table]`, `bp3 repo remove <name>`, and `-h`, normalizing every path via `git -C <path> rev-parse --git-common-dir` + `Unix.realpath` so worktrees map to the main repo. Wire **fail-fast** auto-registration (`repo add "$target"`) into `bin/bp3` `skills_install()` (for `bp3 init` / `bp3 skills install`) and `bp3 init-repo` in `main.ml`. Prove with `test/unit/test_repo.ml` and `test/repo.sh`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 repo list
usage: bp3 init ...
$ ls src/repo/
ls: src/repo/: No such file or directory
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ (cd /tmp/fake-predictor && ./bin/bp3 init)
  -> installs skills AND registers predictor in repos (fail-fast on error)
$ ./bin/bp3 repo list --format table
name       root_path                      last_seen_at
predictor  /private/tmp/fake-predictor    2026-11-24T...
$ ./bin/bp3 repo add /tmp/fake-predictor --name predictor
  -> idempotent upsert (updates last_seen_at), rc 0
$ ./bin/bp3 repo add /tmp/other-repo --name predictor
  -> rc 1, error.code:"E_EXISTS" (name already bound to different path)
$ ./bin/bp3 repo remove predictor
{"ok":true,"removed":"predictor"}
```

```yaml
objective: ship src/repo/ (bp3_repo) with bp3 repo add|list|remove, canonical worktree dedup, and fail-fast auto-registration during bp3 init / skills install / init-repo
prove by:
  - dune test (test/unit/test_repo.ml: known cases + QCheck2 slugify property)
  - test/repo.sh (explicit add, cwd default, worktree->main root dedup, duplicate name E_EXISTS, list json & table, remove + E_NOT_FOUND, bp3 init & init-repo fail-fast auto-register)
  - make check-full
done when: all unit tests, test/repo.sh, and make check-full pass with zero pollution to ~/.local/share/bp3/bp3.sqlite
```

## Diagram

```text
bp3 init / bp3 skills install ──► skills_install() ──► fail-fast: repo add "$target"
bp3 init-repo                 ──► main.ml          ──► Repo_store.add root
bp3 repo add [<path>] [--name]──► Repo_cli.run     ──► git -C <path> rev-parse --git-common-dir
                                                         └──► Unix.realpath -> Db.slugify
                                                                └──► repos table (BEGIN IMMEDIATE)
```

## Pseudocode

```python
def resolve_main_repo_root(path: str) -> str:
    common = git_out(path, ["rev-parse", "--git-common-dir"])
    if not common:
        raise E_NOT_FOUND("not a git repository")
    abs_common = realpath(join(path, common))
    return dirname(abs_common) if basename(abs_common) == ".git" else abs_common

def repo_add(db, path_opt, name_opt):
    root = resolve_main_repo_root(path_opt or current_root())
    name = validate_explicit_slug(name_opt) if name_opt else slugify(basename(root))
    with tx_immediate(db):
        by_name = find_by_name(db, name)
        if by_name and by_name.root_path != root:
            raise E_EXISTS(f"repo name {name} already points to {by_name.root_path}")
        by_path = find_by_path(db, root)
        if by_path and by_path.name != name:
            raise E_EXISTS(f"repo path {root} already registered as {by_path.name}")
        return upsert_repo(db, name, root, now_ts())
```

## Tables

| Field | Value |
|---|---|
| Intent | maintain the MacBook's canonical local repo registry in `bp3.sqlite` with zero-friction auto-registration on `bp3 init` / `skills install` / `init-repo` |
| Lane | standard |
| Output | `src/repo/{dune,repo_store.ml,repo_cli.ml}`, `src/quest/{dune,main.ml}` (1-line dispatch + `init-repo` hook), `bin/bp3` (door + fail-fast `skills_install` hook), `test/unit/test_repo.ml`, `test/repo.sh`, `test/suites.tsv` |
| Acceptance | fails today (`bp3 repo` unknown, `src/repo/` absent); passes when `test_repo.ml`, `test/repo.sh`, and `make check-full` pass |
| Depends on | `db.1 - sqlite-foundation` |
| Must not touch | `refs/heads/bp3/*`, `skills/*` |

## Prose

A desk/worktree inside `predictor` (`../predictor.desks/quest-1`) resolves via `--git-common-dir` + `Unix.realpath` to the exact same canonical root as `~/m/predictor`, preventing duplicate rows. `bp3 init` / `bp3 skills install` calls `repo add "$target"` fail-fast whenever the engine binary is executable and `$target` is a git repo (per Round 6 owner call: single local user, fail fast instead of hiding broken registrations).

Edge cases:
- **Non-git path:** `bp3 repo add /tmp/not-a-repo` refuses cleanly with `E_NOT_FOUND` (exit `2`).
- **Explicit `--name` vs auto-derived slug:** Auto-derived names run through `Db.slugify` (handling spaces/underscores/dots/uppercase); explicit `--name` is checked strictly with `Db.valid_slug` (`E_USAGE` on invalid characters).
- **Removing a repo with historical tickets:** Because `tickets.to_repo` has no SQL `FOREIGN KEY` (Round 4), `bp3 repo remove <name>` unregisters the repo cleanly without deleting or blocking on historical tickets.

## Tests

- **Known cases (`test/unit/test_repo.ml` + `test/repo.sh`):** add explicit path, cwd default, worktree→main root dedup, idempotent re-add, duplicate name `E_EXISTS`, duplicate path different name `E_EXISTS`, `list` JSON & `--format table`, `remove` & `E_NOT_FOUND`, fail-fast auto-register via `bp3 init` & `bp3 init-repo`.
- **Property-based (QCheck2 in `test/unit/test_repo.ml`):** `Db.slugify` over arbitrary non-empty ASCII directory names (including spaces, underscores, dots, uppercase) always produces either a `Db.valid_slug` string or an explicit `Error` when no alphanumeric characters exist.
