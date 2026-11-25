---
date: 2026-11-25
quest: ../../QUEST.md
node: cleanup.1
status: active
---

# cleanup.1 - drop-makefile-root-hack: delete `Makefile` `--root=.` workaround and tighten `scripts/check-gates`

## TL;DR

Remove the `$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)` workaround from `Makefile:7-8`, remove `( --root=\.)?` from `scripts/check-gates:11,51-52` so the hack cannot creep back in, add a negative case in `test/check-tiers.sh` confirming `scripts/check-gates` rejects `dune build --root=.`, and verify `make check` / `make check-full` run cleanly both at repo root and inside a central desk.

## Acceptance gates

Observed today (2026-11-25, `c8bfbb9`):

```text
$ grep -n -- "--root=" Makefile scripts/check-gates
Makefile:7:DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
Makefile:8:DUNE_TEST = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
scripts/check-gates:11:#   dune build of both binaries (SDKROOT= and --root=. allowed)
scripts/check-gates:51:  "$dune build( --root=\\.)? src/quest/main\\.exe src/quest/run_suites\\.exe"
scripts/check-gates:52:  "$dune test( --root=\\.)?"
```

Design trace:

```text
$ grep -n -- "--root=" Makefile scripts/check-gates
# 0 matches
$ ./scripts/check-gates
check-gates: ok
$ ./test/check-tiers.sh
# passes including new check that `dune build --root=.` is rejected by check-gates
$ make check && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: delete the Makefile --root=. nested-worktree hack and enforce its removal in scripts/check-gates
prove by:
  - grep -n -- "--root=" Makefile scripts/check-gates returns 0 matches
  - test/check-tiers.sh asserts scripts/check-gates rejects a Makefile containing `dune build --root=.`
  - make check && make check-full pass (25/25 suites) from inside the central quest desk (no --root=. needed!)
done when: --root=. is gone from Makefile and scripts/check-gates, test/check-tiers.sh proves the tightened gate, and make check-full passes
```

## Diagram

```text
BEFORE:
  Makefile:7-8         dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
  scripts/check-gates  allows `( --root=\.)?`

AFTER:
  Makefile:7-8         dune build   /   dune test
  scripts/check-gates  exact match (no --root=.)  ──► rejects any re-introduced --root=. hack
```

## Pseudocode

```python
# Makefile:7-8
DUNE_BUILD = "$(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build"
DUNE_TEST  = "$(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test"

# scripts/check-gates:51-52
steps_ocaml = [
    r"$dune build src/quest/main\.exe src/quest/run_suites\.exe",
    r"$dune test",
]

# test/check-tiers.sh:
# plant a temp Makefile with `dune build --root=.` and assert `./scripts/check-gates --makefile <tmp>` fails non-zero
```

## Tables

| Field | Value |
|---|---|
| Intent | remove the repo-specific `Makefile` `--root=.` hack now that desks live outside the repo tree |
| Lane | standard |
| Output | `Makefile`, `scripts/check-gates`, `test/check-tiers.sh` |
| Acceptance | fails today (`--root=.` present in `Makefile:7-8` and allowed in `scripts/check-gates:51-52`); passes when removed, rejected by `test/check-tiers.sh`, and `make check-full` passes |
| Depends on | `desks.1 - central-layout-and-worktree` |
| Must not touch | `src/*`, `skills/*`, `CONSTRAINTS.md` |

## Prose

Chesterton's fence: `Makefile:7-8` existed solely because `.bp3/worktrees/<q>` sat inside `/Users/whycz/m/bp3`, so `dune` walked upward, found the outer `dune-project`, and refused to build the inner worktree without `--root=.`. Note on execution order: if this node is authored inside an *existing* legacy `.bp3/worktrees/` quest desk (started before `desks.1`), `dune` in that legacy desk would need `--root=.` until a central desk is used! Because `desks.1` lands first (Wave 1), authoring `cleanup.1` inside a central desk (`~/.bp3/desks/...`) directly dogfoods and proves `dune build` + `dune test` work cleanly without `--root=.`.

## Tests

- **Known cases (`test/check-tiers.sh`):** existing `check-gates` allowlist/mutation tests plus a new mutation case planting `--root=.` on `DUNE_BUILD` and asserting `scripts/check-gates` rejects it.
- **Property-based:** omitted — exact allowlist check over a fixed 7-step `Makefile` gate plan.
