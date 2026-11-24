---
date: 2026-11-23
quest: ../../QUEST.md
node: store.1
status: proposed
---

# store.1 - sqlite-quest-and-metrics-engine: back Store, Metrics, Config, Desks, Warden, and statusline with bp3.sqlite

## TL;DR

Implement the SQLite backend for `Store`, `Metrics_io`, `Config`, `Worktree` desk registry, and `Warden_io` (gated behind `BP3_STORE=sqlite` during this node so existing git-ref fixtures stay 100% green until `tests.1` flips SQLite to default-only and deletes the git-ref plumbing; see `QUEST.md` Open question 1). Preserve every `bp3 q`, `bp3 metrics`, `bp3 warden`, `bp3 config`, and `bp3 harness desk` JSON/table/tree verdict shape identically, enforce append-only `ledger_events` + optimistic `E_STALE_WORLD` concurrency inside `BEGIN IMMEDIATE`, cache immutable `(repo_id, commit_sha) -> changes_json` for fast `bp3 q r`, and update `scripts/agy-statusline` to read `created_at` from `bp3 q r <quest>` instead of `git show refs/heads/bp3/...`.

## Acceptance gates

Observed today:

```text
$ BP3_STORE=sqlite ./bin/bp3 q r
  (env var ignored; still reads refs/heads/bp3/*)
$ grep -n "refs/heads/bp3" scripts/agy-statusline
236:first_ts="$(git -C "$root" show "refs/heads/bp3/quest/${quest}:docs/quests/${quest}/ledger.jsonl" ...
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ export BP3_STORE=sqlite
$ ./bin/bp3 q c demo --type default
$ ./bin/bp3 q demo n c node-1
$ ./bin/bp3 q demo n node-1 e handoff --commit HEAD --reason "impl"
$ ./bin/bp3 q demo n node-1 brief
  -> renders identical cold brief (reading NODE.md & GRADING.md from git at bound SHA)
$ ./bin/bp3 q demo n node-1 e grade --verdict ship --verify-verdict pass --commit HEAD --reason "clean"
$ ./bin/bp3 q demo n node-1 e land --reason "ship"
  -> state:"landed", fin:"node_fin"; zero refs/heads/bp3/* branches created!
$ ./bin/bp3 q r demo
  -> includes created_at; identical verdict shape to git-ref backend
$ ./bin/bp3 warden demo --no-sessions
  -> ok:true, runs all 8 Layer-1 plugs from SQLite state + metrics
$ grep -n "refs/heads/bp3" scripts/agy-statusline
  -> (no matches)
$ make check-full
  -> rc 0 (existing git-ref suites + new SQLite unit/fixture tests all green)
```

```yaml
objective: implement the complete SQLite backend for quest FSM, metrics, config, desks, warden, and statusline with identical CLI contracts and zero git-ref writes
prove by:
  - dune test (test/unit/test_sqlite_store.ml: full FSM lifecycle, E_ILLEGAL_EDGE, E_COMMIT_MISMATCH, E_DIRTY_TREE, E_DEP_CYCLE, E_STALE_WORLD, metrics dedupe, desks CRUD, warden Layer-1 parity)
  - test/sqlite-e2e.sh (runs full quest create -> node -> handoff -> brief -> grade -> land -> metrics -> warden -> agy-statusline under BP3_STORE=sqlite + temp BP3_DB, asserting 0 refs/heads/bp3/* created)
  - make check-full
done when: all SQLite unit tests, test/sqlite-e2e.sh, and existing make check-full suites pass with 100% verdict parity
```

## Diagram

```text
bp3 q / metrics / warden / config / harness desk
       │
       ├──► bp3.sqlite (WAL, BEGIN IMMEDIATE)
       │      ├── quests, nodes, ledger_events (append-only!)
       │      ├── metrics (deduped by repo,quest,node,cycle,run,metric)
       │      ├── desks, kv_config
       │      └── commit_changes_cache (repo_id, commit_sha -> json)
       │
       └──► git (code & worktrees ONLY — zero refs/heads/bp3/* writes!)
              ├── status --porcelain (E_DIRTY_TREE)
              ├── rev-parse --verify <sha> (E_COMMIT_MISMATCH)
              ├── show <sha>:<path> (Brief reads NODE.md / GRADING.md)
              ├── diff-tree <sha> (on cache miss only)
              └── worktree add/remove/list (real desks)
```

## Pseudocode

```python
def append_node_edge(db, repo_id, quest, node, expected_seq, edge_event, new_state):
    with tx_immediate(db):
        cur = query_one(db, "SELECT seq, state FROM nodes WHERE repo_id=? AND quest=? AND node=?",
                        [repo_id, quest, node])
        if cur is None:
            raise E_NOT_FOUND("node", node)
        if cur.seq != expected_seq:
            raise E_STALE_WORLD("node moved; re-read and retry")
        exec(db, "INSERT INTO ledger_events (...) VALUES (...)", edge_event)
        exec(db, "UPDATE nodes SET state=?, cycle=?, bound_sha=?, grade_ok=?, verify_ok=?, "
                 "blocked_reason=?, blocked_checkpoint=?, blocked_since=?, last_commit=?, seq=seq+1 "
                 "WHERE repo_id=? AND quest=? AND node=?", new_state)
```

## Tables

| Field | Value |
|---|---|
| Intent | build and verify the complete SQLite storage backend alongside the git-ref backend so every commit stays green |
| Lane | high-blast-radius |
| Output | `src/quest/store.ml`, `src/quest/metrics_io.ml`, `src/quest/config.ml`, `src/quest/worktree.ml`, `src/warden/warden_io.ml`, `src/quest/render.ml`, `scripts/agy-statusline`, `test/unit/test_sqlite_store.ml`, `test/sqlite-e2e.sh`, `test/suites.tsv` |
| Acceptance | fails today (`BP3_STORE=sqlite` unsupported, `agy-statusline` reads `refs/heads/bp3/`); passes when `test_sqlite_store.ml`, `test/sqlite-e2e.sh`, and `make check-full` pass |
| Depends on | `migrate.1 - import-git-refs-and-export` |
| Must not touch | `skills/*`, existing 12 ref-reading shell suites (migrated in `tests.1`) |

## Prose

Notice how clean the `git` vs `SQLite` separation becomes here: `git` is only called for actual code/worktree questions (`status --porcelain`, `rev-parse`, `show <sha>:NODE.md`, `diff-tree` on cache miss, `worktree`), never for quest bookkeeping. And caching `(repo_id, commit_sha) -> changes_json` in `commit_changes_cache` drops all-quests `bp3 q r` from `0.87s` (158 `git diff-tree` subprocesses) to milliseconds on warm reads!

Edge cases:
- **Dirty checkpoint on `block`:** `Store.make_checkpoint` still creates a real git commit object (`commit-tree`) and stores the SHA string in `ledger_events.checkpoint` — checkpoints capture dirty source files, so they belong in git objects.
- **Land conflict:** Under `induct-inline` and SQLite storage, `land` no longer needs `git merge-tree` between hidden ledger branches (there are no hidden ledger branches); `land` records the `landed` event on the node and advances quest rollup atomically inside SQLite.
- **`hooks.ml` (`bp3 q hooks`):** Fail-open invariant stays intact (if SQLite open fails or busy-times-out, `hooks` still exits `0` cleanly without blocking any agent tool).
