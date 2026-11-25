---
date: 2026-11-23
quest: ../../QUEST.md
node: tests.1
status: proposed
---

# tests.1 - migrate-fixture-suites: flip SQLite to sole backend, isolate BP3_DB in run-suites, delete git-ref plumbing

## TL;DR

Flip SQLite to the **sole** backend (removing the temporary `BP3_STORE` switch), delete the retired git-ref ledger plumbing (`commit_files`, `move_ref`, `create_branch_commit`, `cat-file --batch` in `src/quest/gitx.ml`, plus `legacy_*` ref/path folding in `src/quest/store.ml` and `src/quest/layout.ml`), verify `src/quest/run_suites.ml`'s per-suite temp `BP3_DB` isolation covers every suite, and migrate the 12 test suites (68 direct `refs/heads/bp3/*` assertions) to assert through `bp3 q` / `bp3 db`. Keep the read-only git-ref scanner inside `src/db/db_migrate.ml` so `bp3 db import-refs` continues to work for downstream repos.

## Acceptance gates

Observed today:

```text
$ git grep -n "bp3/node\|bp3/quest\|bp3/graph\|bp3/exp" -- test/ | wc -l
68
$ grep -n "commit_files" src/quest/gitx.ml
217:let commit_files ~branch ~base_tip ~expect_tip ~files ~msg =
```

Design trace:

```text
$ grep -n "commit_files\|move_ref\|legacy_quest_ref_kinds" src/quest/gitx.ml src/quest/store.ml src/quest/layout.ml
  -> (no matches; only db_migrate.ml retains read-only legacy ref import!)
$ ./bin/bp3 db import-refs   # still works on fixture repo with old refs/heads/bp3/*
  -> ok:true, parity_ok:true
$ make check-full
  -> rc 0 (all suites pass in parallel with isolated temp BP3_DB; ~/.local/share/bp3/bp3.sqlite untouched!)
```

```yaml
objective: make bp3.sqlite the sole quest store, isolate BP3_DB across all test suites, migrate all 12 ref-reading suites, and delete obsolete git-ref plumbing
prove by:
  - grep confirms commit_files / move_ref / create_branch_commit / legacy_quest_ref_kinds deleted from gitx.ml, store.ml, layout.ml
  - run-suites injects unique temp BP3_DB per suite (verified: ~/.local/share/bp3/bp3.sqlite mtime unchanged after make check-full)
  - test/db-migrate.sh still green (import-refs works after plumbing deletion)
  - make check-full
done when: SQLite is the sole quest store, zero obsolete git-ref plumbing remains, all migrated suites pass under make check-full, and user's real DB is untouched
```

## Diagram

```text
run_suites.ml (for each suite in test/suites.tsv):
   ├── tmp_db = mktemp("/tmp/bp3-suite-<name>-<pid>.sqlite")
   ├── spawn suite with BP3_DB=tmp_db
   └── cleanup tmp_db (+ -wal, -shm) on exit

DELETE from src/quest/:
   ├── gitx.ml: commit_files, move_ref, create_branch_commit, batch_query, tip_cache, show_cache
   ├── store.ml: first_existing_ref, quest_branch, node_branch, pick_longest, legacy_*_paths
   └── layout.ml: ref_root, quest_ref_kind, legacy_quest_ref_kinds, node_ref_kind, legacy_node_ref_kinds
   (db_migrate.ml keeps self-contained read-only git show/for-each-ref for import-refs!)
```

## Pseudocode

```python
def run_one_suite(suite):
    tmp_dir = mkdtemp(prefix=f"bp3-suite-{suite.name}-")
    tmp_db = join(tmp_dir, "bp3.sqlite")
    try:
        rc = exec_suite(suite.cmd, env={**os.environ, "BP3_DB": tmp_db})
        return rc
    finally:
        rmtree(tmp_dir)
```

## Tables

| Field | Value |
|---|---|
| Intent | complete the cutover cleanly by removing the old git-ref writer/reader and migrating every fixture suite with full DB isolation |
| Lane | high-blast-radius |
| Output | `src/quest/gitx.ml`, `src/quest/store.ml`, `src/quest/layout.ml`, `src/db/db_migrate.ml`, `src/quest/run_suites.ml`, migrated `test/*.sh` and `test/unit/test_layout.ml` |
| Acceptance | fails today (68 direct ref checks in `test/`, `commit_files` in `gitx.ml`); passes when plumbing is deleted and `make check-full` passes |
| Depends on | `store.1 - sqlite-quest-and-metrics-engine` |
| Must not touch | `skills/*` (handled in `skills.1`) |

## Prose

Chesterton's fence: the 12 test suites (`test/blocked.sh`, `context.sh`, `diagram.sh`, `g.sh`, `hooks.sh`, `metrics.sh`, `ready.sh`, `tape.sh`, `worktree.sh`, `unit/test_layout.ml`, etc.) originally inspected `git show bp3/node/...:ledger.jsonl` because git refs were the only way to inspect raw ledger lines. After cutover, those assertions should verify behavior through `bp3 q` verdicts or `bp3 db export-quest` / SQLite inspection — never weaken or skip an assertion!

Edge cases:
- **Standalone test execution (`./test/g.sh` run directly outside `run-suites`):** Each shell suite should ALSO default `BP3_DB` to its own temp repo's `tmp/bp3.sqlite` when `BP3_DB` is unset, so running `./test/g.sh` directly by hand never pollutes `~/.local/share/bp3/bp3.sqlite` either!
- **Retaining `bp3 db import-refs`:** Before deleting `gitx.ml` ref helpers, ensure `db_migrate.ml` holds its own tiny read-only `git for-each-ref` + `git show` calls so `test/db-migrate.sh` keeps passing after `gitx.ml` is slimmed down.
