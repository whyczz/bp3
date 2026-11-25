---
date: 2026-11-23
quest: ../../QUEST.md
node: clean.1
status: active
---

# clean.1 - util-and-dead-code: extract `src/quest/util.ml` and delete dead code

## TL;DR

Extract one tiny `src/quest/util.ml` module (~90 LOC, stdlib+unix+yojson only, zero domain knowledge) holding the primitives currently copy-pasted across `store.ml`, `config.ml`, `worktree.ml`, `hooks.ml`, `release.ml`, `run_suites.ml`, and `tx.ml` (`contains_sub`, `strip_prefix`, `mkdir_p`, `write_file_atomic`, `epoch_of_iso`, and total Yojson field getters), delete the literal dead statements in `cli.ml:40-47` (`ignore has`) and `store.ml:115-118` (no-op `if`), and add `test/unit/test_util.ml` with known cases + QCheck2 roundtrip properties.

## Acceptance gates

Observed today (2026-11-24):

```text
$ rg -n "let (contains_sub|ensure_dir|mkdir_p|strip_prefix|write_file_atomic|member_str|get_str)" src/quest/*.ml
# duplicated across store.ml, config.ml, worktree.ml, release.ml, hooks.ml, run_suites.ml
$ rg -n "ignore has" src/quest/cli.ml
47:    ignore has;
$ rg -n "then grade_required else grade_required" src/quest/store.ml
118:      grade_required else grade_required in
```

Design trace:

```text
$ rg -n "let (contains_sub|ensure_dir|mkdir_p|strip_prefix|write_file_atomic)" src/quest/*.ml
# hits ONLY src/quest/util.ml
$ rg -n "ignore has|then grade_required else grade_required" src/quest/*.ml
# 0 matches
$ make check && make check-full
# rc 0 (pure refactor, zero behavior change)
```

```yaml
objective: eliminate duplicated primitives and literal dead code across src/quest/ with zero behavior change
prove by:
  - test/unit/test_util.ml: unit cases (malformed/null JSON, nested mkdir_p, atomic write, epoch_of_iso, strip_prefix, contains_sub) + QCheck2 roundtrip properties
  - rg check confirming zero duplicate definitions of contains_sub, strip_prefix, mkdir_p, ensure_dir, write_file_atomic outside src/quest/util.ml
  - make check && make check-full (and red-first: green (refactor))
done when: test_util.ml and make check-full pass and all duplicate/dead sites are gone
```

## Diagram

```text
src/quest/util.ml (one home, ~90 LOC)
   ├── string: contains_sub, strip_prefix
   ├── fs:     mkdir_p, write_file_atomic
   ├── time:   epoch_of_iso
   └── json:   member, get_str, get_str_opt, get_int, get_int_opt, get_bool
         │
         ▼ imported by store.ml, config.ml, worktree.ml, hooks.ml, release.ml, tx.ml, run_suites.ml, main.ml
```

## Pseudocode

```python
# Refactor-only node: behavior stays identical.
# 1. Create src/quest/util.ml with the shared helpers.
# 2. Replace local copies in store.ml, config.ml, worktree.ml, hooks.ml, release.ml, tx.ml, claude_tx.ml, pi_tx.ml, agy_tx.ml, run_suites.ml.
# 3. Delete cli.ml:40-47 (`let has = ... ignore has`) and store.ml:115-118 (no-op `if`).
```

## Tables

| Field | Value |
|---|---|
| Intent | give `src/quest/` one tiny, bug-free utility base instead of divergent copies of JSON/fs/string helpers |
| Lane | standard |
| Output | `src/quest/util.ml` (new), `test/unit/test_util.ml` (new), `test/unit/dune`, edits in `store.ml`, `config.ml`, `worktree.ml`, `hooks.ml`, `release.ml`, `cli.ml`, `tx.ml`, `run_suites.ml`, `main.ml` |
| Acceptance | fails today (duplicates + dead code present); passes when single-home grep + `test_util.ml` + `make check-full` pass |
| Depends on | `retire.2 - slim-harness-to-desk` |
| Must not touch | `skills/*`, `bin/bp3`, `CONSTRAINTS.md` |

## Prose

Note on `scripts/red-first`: commit this node with a `refactor(quest): ...` subject so `red-first` runs in refactor mode (`green (refactor)` on parent tests, while `test_util.ml` validates the new module). Keep `util.ml` under ~100 lines — strictly pure/stdlib+unix+yojson primitives with zero domain knowledge (`quest`/`node`/`ledger` never appear in `util.ml`).

## Tests

- **Known cases (`test/unit/test_util.ml`):** `contains_sub` (empty needle/haystack, boundary match, miss), `strip_prefix` (exact, longer, shorter, miss), `mkdir_p` (nested + idempotent), `write_file_atomic` (creates & overwrites cleanly with no leftover `.tmp`), `epoch_of_iso` (valid UTC, malformed), and total JSON getters on missing/null/wrong-type/valid fields.
- **Property-based (QCheck2 in `test/unit/test_util.ml`):** `strip_prefix ~prefix (prefix ^ s) = Some s` and `contains_sub (a ^ b ^ c) b = true` over arbitrary strings.
