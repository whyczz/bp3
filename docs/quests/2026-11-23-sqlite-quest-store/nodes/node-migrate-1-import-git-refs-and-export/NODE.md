---
date: 2026-11-23
quest: ../../QUEST.md
node: migrate.1
status: proposed
---

# migrate.1 - import-git-refs-and-export: idempotent refs/heads/bp3/* importer and flat JSONL exporter

## TL;DR

Implement `src/quest/db_migrate.ml` with **`bp3 db import-refs [--repo <path>]`** (reads every canonical and legacy `refs/heads/bp3/{quest,node,graph,goal,exp}/*` ledger and `metrics.jsonl` from a git repo into `bp3.sqlite`, idempotent on re-run, verifying 100% folded state/cycle/commit/metrics parity against the existing git-ref `Store` fold before committing) and **`bp3 db export-quest <quest> [--out <dir>]`** (writes clean flat `ledger.jsonl` and `metrics.jsonl` snapshots from SQLite). Never deletes local git refs. Proved by `test/db-migrate.sh`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 db import-refs
usage: bp3 init ...
$ ./bin/bp3 db export-quest 2026-11-23-warden-v0
usage: bp3 init ...
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 db import-refs
{"ok":true,"repo":"bp3","quests_imported":34,"nodes_imported":158,"ledger_rows":...,"metric_rows":...,"skipped_existing":0,"parity_ok":true}
$ ./bin/bp3 db import-refs
{"ok":true,"repo":"bp3","quests_imported":0,"nodes_imported":0,"ledger_rows":0,"metric_rows":0,"skipped_existing":34,"parity_ok":true}
$ ./bin/bp3 db export-quest 2026-11-23-warden-v0 --out /tmp/export-demo
{"ok":true,"quest":"2026-11-23-warden-v0","out_dir":"/tmp/export-demo","files":[...]}
```

```yaml
objective: import all existing canonical and legacy refs/heads/bp3/* quest ledgers and metrics into bp3.sqlite with verified parity, plus flat JSONL export
prove by:
  - test/db-migrate.sh (fixture repo with canonical quest/node refs + legacy graph/exp refs + metrics.jsonl -> import -> assert parity_ok=true -> re-import idempotently -> export-quest -> verify exported JSONL matches original lines; verify git refs untouched)
  - live smoke test against bp3's own 195 refs into a temp BP3_DB asserting parity_ok=true
  - make check-full
done when: import-refs achieves 100% fold parity on fixtures and bp3's 34 real quests, re-runs idempotently, export-quest round-trips cleanly, and make check-full passes
```

## Diagram

```text
git repo (refs/heads/bp3/{quest,node,graph,goal,exp}/*)
       │
       │  1. Enumerate all quests & nodes via existing Store/Layout fold
       │  2. Parse every ledger.jsonl line (normalizing legacy edge/state/node-id)
       │  3. Parse every metrics.jsonl sample
       ▼
BEGIN IMMEDIATE (bp3.sqlite)
   ├── INSERT OR IGNORE quests, nodes, ledger_events, metrics
   └── Verify SQLite-folded (state, cycle, bound_sha, deps, metric_count)
       == git-folded (state, cycle, bound_sha, deps, metric_count)
       (mismatch -> ROLLBACK + E_DB_ERROR!)
COMMIT
```

## Pseudocode

```python
def import_refs(db, repo_path):
    repo = repo_ensure_registered(db, repo_path)
    git_quests = store_git_list_quests(repo.root_path)
    with tx_immediate(db):
        imported_q, skipped_q, imported_n, l_rows, m_rows = 0, 0, 0, 0, 0
        for q in git_quests:
            if db_quest_exists(db, repo.name, q):
                skipped_q += 1
                continue
            q_tip, q_state, q_type, q_deps, q_text = store_git_fold_quest(repo.root_path, q)
            db_insert_quest_and_ledger(db, repo.name, q, q_type, q_state, q_deps, q_text)
            imported_q += 1
            for n in store_git_list_nodes(repo.root_path, q):
                _, n_state, n_text = store_git_fold_node(repo.root_path, q, n)
                samples = metrics_git_read_samples(repo.root_path, q, n)
                db_insert_node_ledger_and_metrics(db, repo.name, q, n, n_state, n_text, samples)
                assert_parity(git_state=n_state, db_state=db_fold_node(db, repo.name, q, n))
                imported_n += 1
                l_rows += count_lines(n_text)
                m_rows += len(samples)
    return ok(repo=repo.name, quests_imported=imported_q, nodes_imported=imported_n,
              ledger_rows=l_rows, metric_rows=m_rows, skipped_existing=skipped_q, parity_ok=True)
```

## Tables

| Field | Value |
|---|---|
| Intent | provide a lossless, idempotent migration bridge from git refs to SQLite plus flat JSONL export |
| Lane | standard |
| Output | `src/quest/db_migrate.ml`, `src/quest/main.ml`, `test/db-migrate.sh`, `test/suites.tsv` |
| Acceptance | fails today (`import-refs` / `export-quest` unknown); passes when `test/db-migrate.sh`, live 34-quest temp-DB smoke test, and `make check-full` pass |
| Depends on | `backup.1 - db-backup-and-check` |
| Must not touch | existing `bp3 q` read/write paths (still on git refs until `store.1`), `skills/*` |

## Prose

By running `import-refs` while the legacy git-ref reader is still compiled into `Store`, `migrate.1` can assert **live fold parity** inside the transaction: every imported quest/node's state, cycle, bound commit, deps, and metrics count must match `Store.fold_node` bit-for-bit, or the transaction rolls back loudly. Once `store.1` deletes the git-ref writer, `import-refs` keeps only a tiny self-contained read-only git-ref scanner (so downstream repos like `predictor` can still run `bp3 db import-refs` after upgrading `bp3-q`!).

Edge cases:
- **Pre-rename ledgers (`exp-*`, `submit`/`review`/`check`, `graph_type`):** Normalized to canonical spellings (`node-*`, `handoff`/`grade`/`verify`, `goal_type`) on import so `bp3.sqlite` stays 100% clean canonical data with zero legacy compat cruft in `store.1`.
- **Re-running after partial import:** Transaction-scoped per repo; already-imported quests are skipped cleanly (`skipped_existing`), and metrics deduplicate by the existing `(metric, cycle, run)` key.
- **Unrelated `refs/heads/bp3/*` refs** (like the 3 ancient `bp3/exp2-author` branches with no `quest/` or `node/` prefix): skipped cleanly without failing the import (logged as `ignored_refs` count).
