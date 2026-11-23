---
date: 2026-11-23
quest: ../../QUEST.md
node: clean.2
status: proposed
---

# clean.2 - names-and-desk-hygiene: centralize all CLI spellings in `names.ml` and clean rename residue

## TL;DR

Promote `docs/icebox/2026-11-22-names-constants.md`: move every CLI door, verb, edge, state, flag, and `E_*` error code into `src/quest/names.ml`, derive `Store.reserved_slugs` directly from `Names`, add a unit guard failing on new raw `E_*` string literals outside `names.ml`, fix the stale `bp3 g` header comment in `gitx.ml:1`, and clean internal `e` (old `exp`) variable names and `worktree` doc/comment drift toward `desk`.

## Acceptance gates

Observed today:

```text
$ wc -l src/quest/names.ml
       8 src/quest/names.ml
$ head -n 1 src/quest/gitx.ml
(* gitx — process/git plumbing for bp3 g. No quest knowledge. *)
$ rg -c 'err "E_' src/quest/*.ml | grep -v ':0$' | wc -l
# scattered string literals across main.ml, store.ml, worktree.ml, metrics_io.ml
```

Design trace:

```text
$ rg -n 'err "E_' src/quest/*.ml
# 0 matches (all call `err Names.e_* ...`)
$ head -n 1 src/quest/gitx.ml
(* gitx — process/git plumbing for bp3 q. No quest knowledge. *)
$ dune test
# test_names.ml verifies every E_* code in src/quest/ lives in names.ml and reserved_slugs covers every verb/door in Names
$ make check-full
# rc 0
```

```yaml
objective: make src/quest/names.ml the single home for all CLI spellings and error codes, derive reserved_slugs from it, and clear rename residue
prove by:
  - test/unit/test_names.ml: scans src/quest/*.ml for raw `err "E_` literals (must be 0 outside names.ml) and verifies Store.reserved_slugs is a superset of every door and verb constant in Names
  - test/unit/test_store.ml: legacy exp-era / graph-era / quest-era read folds still pass 100%
  - make check-full
done when: test_names.ml, test_store.ml, and make check-full pass with zero raw `err "E_` literals outside names.ml
```

## Diagram

```text
src/quest/names.ml
   ├── doors:  door_q, door_harness, door_config, door_init_repo, ...
   ├── verbs:  verb_create/c, verb_read/r, verb_update/u, verb_delete/d, verb_brief, verb_warden, ...
   ├── edges:  edge_handoff, edge_grade, edge_verify, edge_land, edge_block, edge_resume
   ├── states: st_todo, st_handed_off, st_approved, st_landed, st_blocked, st_deleted
   ├── flags:  flag_reason, flag_commit, flag_verdict, flag_desk, ...
   └── errors: e_usage, e_not_found, e_exists, e_illegal_edge, e_dirty_tree, ...
         │
         ├──► Store.reserved_slugs (derived, never hand-synced!)
         └──► main.ml, cli.ml, store.ml, worktree.ml, brief.ml, metrics_io.ml, render.ml
```

## Pseudocode

```python
# test/unit/test_names.ml guard:
for ml_file in glob("src/quest/*.ml"):
    if ml_file == "src/quest/names.ml": continue
    assert not re.search(r'\berr\s+"E_[A-Z_]+"', read(ml_file)), f"raw error code in {ml_file}"
assert set(Names.all_doors + Names.all_verbs).issubset(set(Store.reserved_slugs))
```

## Tables

| Field | Value |
|---|---|
| Intent | eliminate scattered string literals and stale rename residue so future renames edit one file |
| Lane | standard |
| Output | `src/quest/names.ml`, `src/quest/store.ml`, `src/quest/main.ml`, `src/quest/cli.ml`, `src/quest/worktree.ml`, `src/quest/gitx.ml`, `src/quest/brief.ml`, `src/quest/metrics_io.ml`, `src/quest/render.ml`, `test/unit/test_names.ml` (new), `test/unit/dune` |
| Acceptance | fails today (only 3 constants in `names.ml`, raw `err "E_` literals everywhere, `gitx.ml:1` says `bp3 g`); passes when `test_names.ml` and `make check-full` pass |
| Depends on | `clean.1 - util-and-dead-code` |
| Must not touch | `skills/*`, `bin/bp3`, `CONSTRAINTS.md`, `Layout.legacy_*` read folds |

## Prose

Preserves `ICEBOX.md`'s rule: skills keep plain words (no templates), while the binary keeps every spelling in `names.ml`. Read-side legacy folds (`Layout.legacy_*`, `Store.fold_edge`, `Store.fold_state_name`) stay untouched so every historical quest in git continues to fold cleanly.

On `worktree` vs `desk`: internal identifiers/comments/help strings use `desk` consistently while keeping `.bp3/worktrees` (via `Layout.desks_root`) and the `bp3 worktree` alias intact unless the owner chooses to break them in a separate migration.
