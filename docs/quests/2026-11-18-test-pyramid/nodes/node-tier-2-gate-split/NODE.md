---
date: 2026-11-18
quest: ../../QUEST.md
node: tier.2
status: proposed
---

# tier.2 - gate-split: make check is the inner loop, check-full is the gate

## TL;DR

`make check` becomes lint plus the unit tier (`dune test` and the JS
unit tests). `make check-full` runs `make check`, builds the binary
once, then calls `run-suites` for the fixture and slow tiers, then
the transcript drift check. `check-fast` folds into `make check`.
`check-changed.sh` selects suites by the `paths` column of
`test/suites.tsv` instead of its own list.
CLAUDE.md, AGENTS.md and readme say which gate is which.

## Acceptance gates

Observed today: `make check` runs all 25 steps serially, 170.40s.

Design trace:

```text
$ time make check
lint ok / dune test ok / node --test ok
real 0m11s
$ time make check-full
... run-suites ok 24/24 / transcripts drift 0
real 0m52s
```

```yaml
objective: split the gate into a seconds-long inner loop and a minute-long grade/land gate fed by one suite table
prove by:
  - time make check                         # 170s today
  - time make check-full                    # target does not exist today
  - grep for suite lists outside test/suites.tsv (Makefile, check-changed.sh, lint line)
  - make check-fast
done when:
  - make check exits 0 in under 15s warm, five runs in a row; the cold time (after dune clean) is reported, not gated
  - make check-full exits 0 in 60s or less, five runs in a row
  - suite names appear in exactly one list, test/suites.tsv; the Makefile lint line derives its shellcheck targets from it; check-changed.sh matches changed paths against its `paths` column
  - make check-fast is an alias of make check (or is removed, with check-tiers.sh updated)
  - check-tiers.sh runs inside the gate (today it runs only in the fast tier)
  - CLAUDE.md and AGENTS.md stay identical and name check-full as the grade/land gate
```

## Diagram

```text
make check       = lint ─► dune test ─► node --test (unit tier)          seconds
make check-full  = make check ─► dune build main.exe ─► run-suites ─► transcripts --check
check-changed.sh ─► reads test/suites.tsv ─► runs the matching rows through run-suites
```

## Pseudocode

```makefile
check: lint
	$(DUNE) test
	node --test test/js/ extensions/bp3-pi/test/
check-full: check
	$(DUNE_BUILD) src/quest/main.exe
	./scripts/run-suites --tier fixture,slow
	./scripts/record-transcripts --check
```

| Field | Value |
|---|---|
| Intent | two gates with clear jobs, one suite list |
| Lane | high-blast-radius (changes what every grade runs) |
| Output | Makefile, `check-changed.sh`, `check-tiers.sh`, CLAUDE.md, AGENTS.md, readme |
| Acceptance | goal block above; fails today (170s, no check-full, three suite lists) |
| Depends on | tier.1, unit.1, js.1 |
| Tests | known cases: check-tiers.sh fixtures for the table-driven selector (`paths` globs to rows); property-based: none, by decision: Makefile and selector wiring over a fixed table |

## Prose

The owner chose unit-only `make check` (2026-11-18). The red chair's
second concern follows from it: graders read "run make check" in
CLAUDE.md and the skills, so the grade/land gate has to move to
`check-full` explicitly. This node moves the Makefile and the
always-loaded docs. tier.3 moves the skills, because skill edits get
their own node and gate.

Lane is high-blast-radius because a mistake here lets a grader ship
on a gate that proves less. The acceptance check that suite names
live in one list is what stops the next added suite from silently
skipping a tier.

`check-tiers.sh` runs only in the fast tier today: this session's
fix to `check-retired-terms.sh` was proven by calling it directly,
not through `make check`. That gap closes here.
