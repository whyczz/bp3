---
date: 2026-11-18
quest: ../../QUEST.md
node: unit.1
status: proposed
---

# unit.1 - lib-split: the engine links into tests

## TL;DR

`src/quest/dune` gains a `(library bp3_quest (wrapped false))` over
every module except `main`, and `main.exe` links it. `test/unit/`
gets its first `(test ...)` stanza, with OUnit2 and QCheck. No file
moves. `dune test` runs real tests for the first time.

## Acceptance gates

Design trace (nothing has run):

```text
$ dune test
test_smoke: case_valid_slug_accepts_a_dated_kebab_slug ok
test_smoke: law_valid_slug_rejects_every_string_containing_a_slash ok (200)
Ran: 2 tests in: 0.01 seconds.  OK

$ ./bin/bp3 q -h | shasum      # same digest as before the split
```

```yaml
objective: make engine modules callable from dune tests without changing the binary's behavior
prove by:
  - dune test 2>&1 | grep -c ' ok'       # 0 today: no test stanza exists
  - help and rollup output from main.exe before and after the split
  - make release (artifact still builds from _build/default/src/quest/main.exe)
done when:
  - dune test runs at least 2 tests (one case_, one law_) and exits 0
  - `bp3 q -h`, `bp3 harness -h` and `bp3 q r <quest>` output is byte-identical before and after the split
  - make release succeeds; Layout.engine_src is unchanged
  - planted mutation: Store.valid_slug accepts "a/b"; the law_ test goes red
```

## Diagram

```text
before                          after
src/quest/dune                  src/quest/dune
  (executable main               (library bp3_quest (wrapped false)
    (libraries yojson unix str))    (modules :standard \ main) ...)
                                 (executable main (modules main)
                                    (libraries bp3_quest))
                                test/unit/dune
                                 (tests (names test_smoke)
                                    (libraries bp3_quest ounit2 qcheck-core qcheck-ounit))
```

## Pseudocode

```python
# test/unit/test_smoke.ml, shown as Python
def case_valid_slug_accepts_a_dated_kebab_slug():
    assert Store.valid_slug("2026-11-18-test-pyramid")

@qcheck(strings_containing("/"))
def law_valid_slug_rejects_every_string_containing_a_slash(s):
    assert not Store.valid_slug(s)
```

| Field | Value |
|---|---|
| Intent | give the engine a unit seam with zero behavior change |
| Lane | standard |
| Output | split `src/quest/dune`, `test/unit/dune`, `test/unit/test_smoke.ml` |
| Acceptance | goal block above; fails today (zero tests run) |
| Depends on | none |
| Tests | known cases: `case_valid_slug_accepts_a_dated_kebab_slug`; property-based: `law_valid_slug_rejects_every_string_containing_a_slash`; fixture: byte-identical help and rollup |

## Prose

Module init is already safe to link: `Gitx.root` reads `BP3_ROOT`
or the cwd, and `git_common_dir` is lazy, so loading the library
spawns nothing (checked 2026-11-18). `main.ml` holds the only
`let () =` entry point.

`(wrapped false)` keeps the module names `Store`, `Hooks` and so on,
so `main.ml` needs no `Bp3_quest.` prefixes and the diff stays in
two dune files plus the test. Both stanzas live in one directory
with disjoint modules, which dune supports. `test/unit/` sits beside
the shell suites; dune ignores the `.sh` and `.mjs` files.

The smoke tests exist to prove the wiring, not to cover anything.
unit.3 and unit.4 carry the real suites. The test name kinds
(`case_`, `law_`, `char_`) start here so every later file follows
them.
