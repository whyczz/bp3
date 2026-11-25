---
date: 2026-11-23
quest: ../../QUEST.md
node: ticket.1
status: proposed
---

# ticket.1 - cross-repo-ticket-queue: src/ticket/ (bp3_ticket) and atomic bp3 ticket CLI

## TL;DR

Build `src/ticket/` (`bp3_ticket`: `dune`, `ticket_store.ml`, `ticket_cli.ml`, depending only on `bp3_db bp3_repo yojson unix` — zero dep on `bp3_quest`) and expose `bp3 ticket add|list|read|claim|unclaim|done|dismiss` + `-h` via a one-line dispatch in `main.ml` + `bin/bp3`. Enforce strict `--to` validation against `repos` inside `BEGIN IMMEDIATE` (`E_NOT_FOUND` exit `2` with `facts: {"repo", "registered": [...]}`), atomic `BEGIN IMMEDIATE` claiming (`E_ALREADY_CLAIMED` exit `1` on contention), `unclaim` (`claimed -> open`, clearing `claimed_by`/`claimed_at`), terminal `done`/`dismissed`, and `E_ILLEGAL_EDGE` carrying ticket-native `facts: {"id", "status", "verb", "legal_verbs"}`. Prove with `test/unit/test_ticket.ml` (Known + QCheck2 state-machine properties) and `test/ticket.sh` (all 3 Quest-level functional fixtures incl. 10-way concurrent claim race).

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 ticket list
usage: bp3 init ...
$ ls src/ticket/
ls: src/ticket/: No such file or directory
```

Design trace:

```text
$ export BP3_DB="$(mktemp -d)/bp3.sqlite"
$ ./bin/bp3 repo add /tmp/fake-bp3 --name bp3
$ ./bin/bp3 ticket add --to nonexistent --title "typo"
  -> rc 2, error.code:"E_NOT_FOUND", facts:{"repo":"nonexistent","registered":["bp3"]}

$ ./bin/bp3 ticket add --from predictor --to bp3 --kind bug --title "host desk check fails" --body "line1\nline2"
{"ok":true,"ticket":{"id":1,"from_repo":"predictor","to_repo":"bp3","kind":"bug","title":"host desk check fails","body":"line1\nline2","status":"open",...}}

$ ./bin/bp3 ticket list --to bp3 --format table
id  to   from       kind  status  claimed_by  title
1   bp3  predictor  bug   open    -           host desk check fails

$ ./bin/bp3 ticket read 1 --format table
  -> prints full ticket metadata + full body, rc 0

# 10 concurrent background claims on ticket 1:
#   exactly 1 returns ok:true (status:"claimed")
#   exactly 9 return rc 1 with error.code:"E_ALREADY_CLAIMED"
#   0 return E_DB_ERROR

$ ./bin/bp3 ticket unclaim 1 --reason "worker backing off"
{"ok":true,"ticket":{"id":1,...,"status":"open","claimed_by":null,"claimed_at":null,...}}

$ ./bin/bp3 ticket done 1 --reason "fixed in v0.4.0"
{"ok":true,"ticket":{"id":1,...,"status":"done","resolution_reason":"fixed in v0.4.0",...}}

$ ./bin/bp3 ticket done 1 --reason "again"
  -> rc 1, error.code:"E_ILLEGAL_EDGE", facts:{"id":1,"status":"done","verb":"done","legal_verbs":[]}
```

```yaml
objective: provide src/ticket/ (bp3_ticket) with strict --to validation, single-ticket read, unclaim, atomic multi-agent claiming, and full Quest-level functional tests
prove by:
  - grep -v bp3_quest src/ticket/dune (zero upward dependency on bp3_quest)
  - dune test (test/unit/test_ticket.ml: known cases + QCheck2 state-machine transition invariant property)
  - test/ticket.sh (all 3 Quest-level functional fixtures: happy path across 2 repos, strict --to + 10-way concurrent claim race + terminal E_ILLEGAL_EDGE, cross-surface restart consistency)
  - make check-full
done when: all unit tests and test/ticket.sh (including 10-way concurrent claim race with 0 E_DB_ERROR) pass and make check-full is green
```

## Diagram

```text
  predictor session                  bp3.sqlite (WAL)                   bp3 session
  ─────────────────                  ────────────────                   ───────────
  bp3 ticket add --to bp3  ──►  BEGIN IMMEDIATE
  (never touches ~/m/bp3!)      verify 'bp3' in repos (else E_NOT_FOUND)
                                INSERT tickets (status='open')
                                           │
                                           │  ◄──  bp3 ticket list --to bp3
                                           │  ◄──  bp3 ticket read 1
                                           │  ◄──  bp3 ticket claim 1 --by sess-A
                                  BEGIN IMMEDIATE: UPDATE WHERE id=1 AND status='open'
                                  changes()==1 ? ok : E_ALREADY_CLAIMED
                                           │
                                    [open] ◄──unclaim──► [claimed]
                                      │                     │
                                      └───done / dismiss────┴──► [done | dismissed] (terminal)
```

## Pseudocode

```python
def ticket_add(db, to_repo, from_repo_opt, kind, title, body):
    assert valid_kind(kind) and title.strip() != ""
    from_repo = from_repo_opt or infer_caller_repo(db) or "unknown"
    with tx_immediate(db):
        registered = repo_list_names(db)
        if to_repo not in registered:
            raise E_NOT_FOUND(repo=to_repo, registered=registered)
        tid = insert_ticket(db, from_repo, to_repo, kind, title, body, "open", now_ts())
        return get_ticket(db, tid)

def ticket_claim(db, tid: int, by: str):
    with tx_immediate(db):
        row = get_ticket(db, tid)
        if row is None:
            raise E_NOT_FOUND(ticket=tid)
        if row.status != "open":
            if row.status == "claimed":
                raise E_ALREADY_CLAIMED(id=tid, status=row.status, claimed_by=row.claimed_by)
            raise E_ILLEGAL_EDGE(id=tid, status=row.status, verb="claim", legal_verbs=[])
        exec(db, "UPDATE tickets SET status='claimed', claimed_by=?, claimed_at=? WHERE id=? AND status='open'",
             [by, now_ts(), tid])
        assert sqlite3_changes(db) == 1
        return get_ticket(db, tid)

def ticket_unclaim(db, tid: int, reason: str):
    assert reason.strip() != ""
    with tx_immediate(db):
        row = get_ticket(db, tid)
        if row is None:
            raise E_NOT_FOUND(ticket=tid)
        if row.status != "claimed":
            raise E_ILLEGAL_EDGE(id=tid, status=row.status, verb="unclaim", legal_verbs=legal_verbs(row.status))
        exec(db, "UPDATE tickets SET status='open', claimed_by=NULL, claimed_at=NULL WHERE id=?", [tid])
        return get_ticket(db, tid)
```

## Tables

| Field | Value |
|---|---|
| Intent | implement the cross-repo ticket queue in `src/ticket/` (`bp3_ticket`) with strict `--to`, `read`, `unclaim`, and atomic WAL claims |
| Lane | standard |
| Output | `src/ticket/{dune,ticket_store.ml,ticket_cli.ml}`, `src/quest/{dune,main.ml}` (1-line dispatch), `bin/bp3`, `test/unit/test_ticket.ml`, `test/ticket.sh`, `test/suites.tsv` |
| Acceptance | fails today (`bp3 ticket` unknown, `src/ticket/` absent); passes when `test_ticket.ml`, `test/ticket.sh` (incl. 10-way claim race), and `make check-full` pass |
| Depends on | `compat.1 - install-hook-and-test-isolation` |
| Must not touch | `refs/heads/bp3/*`, `skills/*` |

## Prose

`bp3 ticket add` never touches the target repo's git working tree or branches. When `--from` is omitted inside a git repo, `Repo_store.infer_from_root` resolves the main repo via `--git-common-dir` + `Unix.realpath` and looks up its registered `repos.name` (supporting custom `--name` aliases), falling back to `Db.slugify(basename)` or `"unknown"` outside git.

Edge cases:
- **Unregistered `--to` target:** Refused with `E_NOT_FOUND` (exit `2`) carrying `facts: {"repo": "<slug>", "registered": [...]}` (Round 3 strict call).
- **`claim` on terminal `done`/`dismissed` vs already `claimed`:** `claimed` returns `E_ALREADY_CLAIMED` (`{id, status, claimed_by}`); terminal `done`/`dismissed` returns `E_ILLEGAL_EDGE` (`{id, status, verb: "claim", legal_verbs: []}`).
- **Empty `--title` or `--reason` / non-int `<id>` / invalid `--kind` or `--status`:** Refused with `E_USAGE` (exit `2`) before opening a write transaction.

## Tests

- **Known cases (`test/unit/test_ticket.ml` + `test/ticket.sh`):** strict `--to` `E_NOT_FOUND` with `facts.registered`, `add`/`list`/`read` (JSON + `--format table` full `body`), `claim`, `unclaim` (`claimed -> open` clearing `claimed_by`/`claimed_at`), `done`/`dismiss` from both `open` and `claimed`, `E_ILLEGAL_EDGE` facts shape, 10-way parallel claim race (1 ok, 9 `E_ALREADY_CLAIMED`, 0 `E_DB_ERROR`), cross-process restart persistence & `bp3 db info` count agreement.
- **Property-based (QCheck2 in `test/unit/test_ticket.ml`):** arbitrary sequences of `{claim, unclaim, done, dismiss}` from `open` always preserve: (1) terminal states (`done`, `dismissed`) never transition again, (2) `status = "claimed" <=> claimed_by <> None && claimed_at <> None`, and (3) legal-verb table matches actual accepted/refused moves 100%.
