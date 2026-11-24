---
date: 2026-11-23
quest: ../../QUEST.md
node: drop.1
status: proposed
---

# drop.1 - cross-repo-drop-queue: atomic cross-repo drops via bp3 drop

## TL;DR

Add `src/quest/drop_store.ml` and the `bp3 drop` CLI door (`add`, `list`, `claim`, `done`, `dismiss`, `-h`) backed by `drops` in `bp3.sqlite`. Enforce atomic `BEGIN IMMEDIATE` claiming (`E_ALREADY_CLAIMED` on contention), auto-infer `--from` from the caller's repo when omitted, support filtering (`--to`, `--from`, `--status`, `--format json|table`), and prove concurrency safety with a 10-way parallel claim race test in `test/drop.sh` plus pure/DB unit tests in `test/unit/test_drop.ml`.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 drop list
usage: bp3 init ...
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 drop add --from predictor --to bp3 --kind bug --title "host desk check fails" --body "step 1..."
{"ok":true,"drop":{"id":1,"from_repo":"predictor","to_repo":"bp3","kind":"bug","title":"host desk check fails","body":"step 1...","status":"open",...}}

$ ./bin/bp3 drop list --to bp3 --format table
id  to   from       kind  status  claimed_by  title
1   bp3  predictor  bug   open    -           host desk check fails

# 10 concurrent background claims on drop 1:
#   exactly 1 returns ok:true (status:"claimed")
#   exactly 9 return rc 1 with error.code:"E_ALREADY_CLAIMED"
#   0 return E_DB_ERROR

$ ./bin/bp3 drop done 1 --reason "fixed in 2026-11-24-host-desk"
{"ok":true,"drop":{"id":1,...,"status":"done","resolution_reason":"fixed in 2026-11-24-host-desk",...}}
```

```yaml
objective: provide a transactional cross-repo drop queue with atomic multi-agent claiming and structured CLI output
prove by:
  - dune test (test/unit/test_drop.ml: validation, add/list filters, state transitions open->claimed->done|dismissed, open->done|dismissed, illegal transitions on terminal drops)
  - test/drop.sh (end-to-end CLI flow, --from inference from git repo, --format table, 10-way concurrent claim race asserting 1 ok + 9 E_ALREADY_CLAIMED)
  - make check-full
done when: all unit tests and test/drop.sh (including concurrent claim test) pass and make check-full is green
```

## Diagram

```text
  predictor session                  bp3.sqlite (WAL)                  bp3 session
  ─────────────────                  ────────────────                  ───────────
  bp3 drop add --to bp3  ──►  INSERT drops (status='open')
  (never touches ~/m/bp3!)                │
                                          │  ◄──  bp3 drop list --to bp3
                                          │  ◄──  bp3 drop claim 1 --by sess-A
                                    BEGIN IMMEDIATE
                                    UPDATE drops SET status='claimed'
                                    WHERE id=1 AND status='open'
                                    changes()==1 ? ok : E_ALREADY_CLAIMED
                                          │
                                          │  ◄──  bp3 drop done 1 --reason "..."
                                    status='done'
```

## Pseudocode

```python
def drop_claim(db, drop_id: int, by: str):
    with tx_immediate(db):
        row = get_drop(db, drop_id)
        if row is None:
            raise E_NOT_FOUND(f"drop {drop_id}")
        if row.status != "open":
            raise E_ALREADY_CLAIMED(id=drop_id, status=row.status, claimed_by=row.claimed_by)
        exec(db,
             "UPDATE drops SET status='claimed', claimed_by=?, claimed_at=? "
             "WHERE id=? AND status='open'",
             [by, now_ts(), drop_id])
        assert sqlite3_changes(db) == 1
        return get_drop(db, drop_id)

def drop_resolve(db, drop_id: int, new_status: str, reason: str):
    assert new_status in ("done", "dismissed")
    assert reason.strip() != ""
    with tx_immediate(db):
        row = get_drop(db, drop_id)
        if row is None:
            raise E_NOT_FOUND(f"drop {drop_id}")
        if row.status in ("done", "dismissed"):
            raise E_ILLEGAL_EDGE(state=row.status, edge=new_status)
        exec(db,
             "UPDATE drops SET status=?, resolved_at=?, resolution_reason=? WHERE id=?",
             [new_status, now_ts(), reason, drop_id])
        return get_drop(db, drop_id)
```

## Tables

| Field | Value |
|---|---|
| Intent | implement the cross-repo drop queue with atomic claims and typed JSON/table verdicts |
| Lane | standard |
| Output | `src/quest/drop_store.ml`, `src/quest/main.ml`, `bin/bp3`, `test/unit/test_drop.ml`, `test/drop.sh`, `test/suites.tsv` |
| Acceptance | fails today (`bp3 drop` unknown door); passes when `test_drop.ml`, `test/drop.sh` (including 10-way claim race), and `make check-full` pass |
| Depends on | `db.1 - sqlite-foundation`, `repo.1 - repo-registry` |
| Must not touch | `refs/heads/bp3/*`, `skills/*` |

## Prose

`bp3 drop add` never writes into the target repo's git tree or branches — that's the whole point when `predictor` drops a `bp3` bug while `~/m/bp3` is mid-quest. If `--from` is omitted inside a git repo, `drop_store` resolves the caller's repo name from `repos` (or derives the slug from the repo root basename and auto-registers it in `repos`).

Edge cases:
- **Unregistered `--to` target:** Accepted if `Store.valid_slug target` holds; returns `"warnings": ["W_REPO_UNREGISTERED"]` when `--to` is not yet in `repos` so you can drop items for a repo before cloning/registering it (see `QUEST.md` Open question 1).
- **Empty title or reason:** `--title ""` on `add` and missing/empty `--reason` on `done`/`dismiss` fail with `E_USAGE` (exit 2).
- **Double resolution:** `done` or `dismiss` on an already `done`/`dismissed` drop refuses with `E_ILLEGAL_EDGE` (exit 1).
- **Invalid `--kind` or `--status`:** Refused with `E_USAGE` (exit 2) before touching SQLite.
