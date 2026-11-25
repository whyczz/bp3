---
date: 2026-11-23
quest: ../../QUEST.md
node: clean.2
status: active
---

# clean.2 - names-and-desk-hygiene: centralize all `src/quest/` CLI spellings in `names.ml`

## TL;DR

Promote `docs/icebox/2026-11-22-names-constants.md`: move every CLI door, verb, edge, state, flag, and `E_*` error code used in `src/quest/*.ml` into `src/quest/names.ml`, derive `Store.reserved_slugs` directly from `Names` (adding `"warden"` and freeing retired verbs `supervisor`, `watch`, `backtest`, `init-check`, `find-tape`, `n`, `e`), add `test/unit/test_names.ml` failing on any raw `err "E_..."` literal in `src/quest/*.ml` outside `names.ml`, fix the stale `bp3 g` header comment in `gitx.ml:1`, and clean internal `e` (old `exp`) variable names and `worktree` comment/help drift toward `desk`.

## Acceptance gates

Observed today (2026-11-24):

```text
$ wc -l src/quest/names.ml
       8 src/quest/names.ml
$ head -n 1 src/quest/gitx.ml
(* gitx — process/git plumbing for bp3 g. No quest knowledge. *)
$ rg -c 'err "E_' src/quest/*.ml | grep -v ':0$'
# scattered raw E_* string literals across main.ml, release_io.ml, worktree.ml, store.ml, gitx.ml, config.ml
```

Design trace:

```text
$ rg -n 'err "E_' src/quest/*.ml
# 0 matches (all call `err Names.e_* ...`)
$ head -n 1 src/quest/gitx.ml
(* gitx — process/git plumbing for bp3 q. No quest knowledge. *)
$ dune test
# test_names.ml verifies 0 raw err "E_ in src/quest/*.ml outside names.ml,
# Store.reserved_slugs covers every surviving door/verb + "warden" and frees retired verbs
$ make check && make check-full
# rc 0
```

```yaml
objective: make src/quest/names.ml the single home for all src/quest/ CLI spellings and error codes, derive reserved_slugs from it (+ warden, - retired), and clear rename residue
prove by:
  - test/unit/test_names.ml: scans src/quest/*.ml for raw `err "E_` literals (must be 0 outside names.ml), verifies Store.reserved_slugs is a superset of every door and verb in Names (including "warden") and excludes retired supervisor/watch/backtest/init-check/find-tape/n/e
  - test/unit/test_store.ml: legacy exp-era / graph-era / quest-era read folds still pass 100%
  - make check && make check-full
done when: test_names.ml, test_store.ml, and make check-full pass with zero raw `err "E_` literals in src/quest/*.ml outside names.ml
```

## Diagram

```text
src/quest/names.ml
   ├── doors:  door_q, door_harness, door_worktree, door_config, door_init_repo, door_warden, door_release, door_db, door_repo, door_ticket, ...
   ├── verbs:  verb_create/c, verb_read/r, verb_update/u, verb_delete/d, verb_brief, verb_dep, verb_diagram, verb_metrics, ...
   ├── edges:  edge_handoff, edge_grade, edge_verify, edge_land, edge_block, edge_resume
   ├── states: st_todo, st_handed_off, st_approved, st_landed, st_blocked, st_deleted
   ├── flags:  flag_reason, flag_commit, flag_verdict, flag_desk, ...
   └── errors: e_usage, e_not_found, e_exists, e_illegal_edge, e_dirty_tree, ...
         │
         ├──► Store.reserved_slugs (derived from Names, + "warden", - retired verbs)
         └──► main.ml, cli.ml, store.ml, worktree.ml, brief.ml, metrics_io.ml, render.ml, release_io.ml, gitx.ml, config.ml
```

## Pseudocode

```python
# test/unit/test_names.ml guard:
for ml_file in glob("src/quest/*.ml"):
    if ml_file == "src/quest/names.ml": continue
    assert not re.search(r'\berr\s+"E_[A-Z_]+"', read(ml_file)), f"raw error code in {ml_file}"
assert set(Names.all_doors + Names.all_verbs).issubset(set(Store.reserved_slugs))
assert "warden" in Store.reserved_slugs
for retired in ["supervisor", "watch", "backtest", "init-check", "find-tape", "n", "e"]:
    assert retired not in Store.reserved_slugs
```

## Tables

| Field | Value |
|---|---|
| Intent | eliminate scattered string literals and stale rename residue across `src/quest/` so future renames edit one file |
| Lane | standard |
| Output | `src/quest/names.ml`, `src/quest/{store.ml,main.ml,cli.ml,worktree.ml,gitx.ml,brief.ml,metrics_io.ml,render.ml,release_io.ml,config.ml}`, `test/unit/test_names.ml` (new), `test/unit/dune` |
| Acceptance | fails today (only 3 constants in `names.ml`, raw `err "E_` literals across `src/quest/`, `gitx.ml:1` says `bp3 g`, `"warden"` missing from `reserved_slugs`); passes when `test_names.ml` and `make check-full` pass |
| Depends on | `clean.1 - util-and-dead-code` |
| Must not touch | `skills/*`, `bin/bp3`, `CONSTRAINTS.md`, `Layout.legacy_*` read folds, `src/db/*`, `src/repo/*`, `src/ticket/*` |

## Prose

Preserves `ICEBOX.md`'s rule: skills keep plain words (no templates), while the binary keeps every spelling in `names.ml`. Scopes strictly to `src/quest/*.ml` because `src/db/`, `src/repo/`, and `src/ticket/` are lower-level dune libraries (they join `bp3_core` in `split-src-quest`). Read-side legacy folds (`Layout.legacy_*`, `Store.fold_edge`, `Store.fold_state_name`) stay untouched so every historical quest in git continues to fold cleanly.

## Tests

- **Known cases (`test/unit/test_names.ml`):** source scan asserting 0 raw `err "E_..."` literals across `src/quest/*.ml` outside `names.ml`; `Store.reserved_slugs` superset check over `Names.all_doors` and `Names.all_verbs` (including `"warden"`); negative check confirming retired verbs (`supervisor`, `watch`, `backtest`, `init-check`, `find-tape`, `n`, `e`) are no longer reserved; `test_store.ml` legacy fold checks.
- **Property-based:** omitted — static source scan and finite enum coverage over `Names`.
