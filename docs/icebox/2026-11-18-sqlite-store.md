---
status: frozen
date: 2026-11-18
promoted: null
---

# SQLite store: runtime state off JSON files, maybe off git

## Context

Frozen 2026-11-18 after a `make check` speed session on
`master`. That session measured the cost of git as a
database: one `bp3 g r` spawned 185 git processes (129
repeated `rev-parse --git-common-dir`, plus a `sh` and a
leaked temp file per call before the direct-exec fix).
`make check` went 302s → 221s by fixing the plumbing
(direct `Unix.create_process_env`, one version scan per
call, the `cat-file --batch` reader actually enabled,
common-dir memo). The 57 spawns left per call are 55 for-each-ref
calls, one per graph, from the version scan.

Owner question, verbatim: "use sqlite for everything" instead
of "putting any state across git worktrees". Two recorded
decisions stand against SQLite as the record:
[engine-core GRAPH.md:195](../graphs/2026-11-07-bp3-mvp-engine-core/GRAPH.md)
("no SQLite Board") and
[supervisor GRAPH.md:279](../graphs/2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement/GRAPH.md)
("SQLite/Redis as truth" out of scope, rebuildable index later).

State today has two homes:

- **Record:** `ledger.jsonl` on `refs/heads/bp3/graph/*` and
  `bp3/node/*`, landed by CAS (`git update-ref new old`).
  Travels with clones and PRs.
- **Runtime:** JSON files under `.git/bp3/` (shared by all
  worktrees): `runs/`, `links/`, `claims/`, `by-session/`,
  `desks/`, `run-lifecycle-derivations/`, `config.json`
  (`src/graph/config.ml`).

## Sketch

Three tiers; thaw picks how far to go. Each tier stands alone.

```text
today:  bp3 g ─> git refs (record) + .git/bp3/*.json (runtime)
tier 1: bp3 g ─> git refs (record) + .git/bp3/bp3.sqlite (runtime)
tier 2: + bp3.sqlite caches ledger folds keyed by tip sha (rebuildable)
tier 3: bp3.sqlite is the record; ledger.jsonl exported at land
```

- **Tier 1 (smallest):** one `.git/bp3/bp3.sqlite` (WAL,
  `busy_timeout`) replaces the runtime JSON dirs. Claims and
  links become rows under transactions instead of
  `write_file_atomic` races. Ledger and refs untouched.
- **Tier 2:** a read index of ledger lines `(graph, node,
  edge, ts, cycle, commit, tip_sha)`; a stale tip means
  re-fold. Writes still land through git CAS. Same shape as
  the miner's `ledger_facts` table
  ([2026-11-17-tape-scraper-sqlite.md](2026-11-17-tape-scraper-sqlite.md)).
- **Tier 3 (owner's "everything"):** DB is truth; git carries
  code commits plus an exported ledger at land so PRs still
  show the story.

Deliberately not: no server, no ORM, no history migration in
tiers 1–2.

## Blockers

- **Speed may no longer be the reason.** After the
  2026-11-18 fixes a call is ~0.3s; batching the 55
  for-each-ref calls may close the gap without a DB. The case
  for SQLite has to be simplicity or correctness, measured.
- **OCaml binding + host packaging.** `sqlite3-ocaml` needs
  libsqlite3; the `bp3-g` host binary must still install
  cleanly on a stranger's machine.
- **Tier 3 reverses two recorded decisions** and loses what
  git gives free: CAS via `update-ref`, state that travels
  with `git clone`/PRs, `git log` as history. A fresh clone
  would have no state. Owner re-decides with a red chair.
- **Fixture tests read refs directly** (`test/hooks.sh`:
  `git show bp3/node/...:ledger.jsonl`); tier 3 rewrites
  them.
- **One DB file or two:** the miner DB is delete-and-rebuild;
  the runtime DB is not. Likely separate files; decide with
  the tape scraper.

## Promotion trigger

Thaw when any of these happens: a JSON-file race corrupts
or loses a claim/link in `.git/bp3/`; a `bp3 g` call measures
>1s again after the for-each-ref batching; or the tape scraper
thaws and forces the DB-home decision.
