---
date: 2026-11-23
quest: ../../QUEST.md
node: retire.1
status: active
---

# retire.1 - drop-muse-workflows-and-pi-ext: remove 2,925+ LOC of unused JS/TS engines and `lang node`

## TL;DR

Delete `skills/induct/workflows/*.js` (2,245 LOC), `.agents/workflows/*.js`, `extensions/bp3-pi/` (622 LOC), `test/pi-discovery.mjs` (58 LOC), and their obsolete test suites (`test/induct*.mjs`, `test/node-loop.test.mjs`, `test/induct.sh`, `test/js-unit.sh`, `test/transcripts.sh`, `test/fake-bp3/`, `scripts/record-transcripts`). Remove `lang node` and the `harness extensions` row from `CONSTRAINTS.md` with the owner's 2026-11-24 sign-off row. Move all 4 workflow names (`node-loop`, `induct-grade`, `induct-land`, `induct-node`) into `bin/bp3` `RETIRED_WORKFLOWS` (pruning `.agents/workflows/*.js` and empty `.agents/workflows/` dir on `skills install`), drop `node --check` and `./scripts/run-suites --tier unit` from `Makefile` / `scripts/check-gates` / `test/check-tiers.sh` (cleaning `scripts/shell-files --node`, `scripts/check-constraints`, and `scripts/red-first:104`), and update workflow assertions in `test/mode.sh` and `test/skills.sh`.

## Acceptance gates

Observed today (2026-11-24):

```text
$ ls skills/induct/workflows/ extensions/bp3-pi/ test/pi-discovery.mjs
test/pi-discovery.mjs
extensions/bp3-pi/: index.ts  package.json  README.md  roles  src  test
skills/induct/workflows/: induct-grade.js  induct-land.js  induct-node.js  node-loop.js
```

Design trace:

```text
$ ls skills/induct/workflows extensions/bp3-pi .agents/workflows test/pi-discovery.mjs 2>&1
No such file or directory
$ ./scripts/check-constraints
check-constraints: ok (3 languages, ...)
$ BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install
  - prunes any leftover .agents/workflows/{node-loop,induct-grade,induct-land,induct-node}.js and removes empty .agents/workflows/
$ make check && make check-full
  - rc 0 (32/32 suites, 0 JS/TS files, check = lint + dune build + dune test)
```

```yaml
objective: delete the unused Muse JS workflows, bp3-pi extension, test/pi-discovery.mjs, and lang node cleanly with zero dangling references or broken gates
prove by:
  - test ! -e skills/induct/workflows && test ! -e extensions/bp3-pi && test ! -e .agents/workflows && test ! -e test/pi-discovery.mjs
  - ./scripts/check-constraints (3 languages: ocaml, bash, zsh) && ./scripts/check-gates
  - test/skills.sh (verifies bp3 skills install prunes all 4 retired workflow renders + empty .agents/workflows dir)
  - test/mode.sh && test/check-tiers.sh
  - make check && make check-full
done when: all deleted trees are gone, CONSTRAINTS.md carries the 2026-11-24 owner removal sign-off row dropping lang node and harness extensions, and make check-full passes
```

## Diagram

```text
DELETE:
  skills/induct/workflows/*.js   (2,245 LOC)
  .agents/workflows/*.js         (generated copies)
  extensions/bp3-pi/**           (622 LOC + tests)
  test/pi-discovery.mjs          (58 LOC)
  test/induct*, test/node-loop*, test/js-unit.sh, test/transcripts.sh, test/fake-bp3/, scripts/record-transcripts

UPDATE:
  bin/bp3                  (move all 4 WORKFLOW_NAMES into RETIRED_WORKFLOWS; prune empty .agents/workflows/; skills check checks SKILL.md renders only)
  Makefile                 (drop `node --check` line in lint; drop `./scripts/run-suites --tier unit` from check)
  scripts/check-gates      (drop node --check step + --tier unit step in allowlist)
  scripts/check-constraints (handle absent `lang node` cleanly under set -e)
  scripts/shell-files      (retire --node mode)
  scripts/red-first        (remove js-unit special case at line 104)
  test/suites.tsv          (remove bp3-pi, js-unit, transcripts, induct rows -> 32 suites)
  test/check-tiers.sh, test/skills.sh, test/mode.sh
  CONSTRAINTS.md           (drop `lang node` + `harness extensions` row with 2026-11-24 owner sign-off row)
```

## Pseudocode

```python
def retire_js_engines():
    assert git_tag_exists("archive/pre-codebase-diet")
    delete_trees([
        "skills/induct/workflows",
        ".agents/workflows",
        "extensions/bp3-pi",
        "test/pi-discovery.mjs",
        "test/fake-bp3",
        "scripts/record-transcripts",
        "test/induct.sh", "test/js-unit.sh", "test/transcripts.sh",
        "test/induct-*.test.mjs", "test/node-loop.test.mjs",
    ])
    update_bin_bp3_retire_all_workflows_and_rmdir_empty()
    update_makefile_check_gates_shell_files_check_constraints_red_first()
    update_suites_tsv_and_tests()
    update_constraints_with_owner_signoff()
```

## Tables

| Field | Value |
|---|---|
| Intent | remove 2,925+ LOC of dead Muse JS workflows, `bp3-pi`, `test/pi-discovery.mjs`, and `lang node` + their maintenance/CI tax |
| Lane | high-blast-radius |
| Output | deletions above + updated `bin/bp3`, `Makefile`, `scripts/{check-gates,check-constraints,shell-files,red-first}`, `test/{suites.tsv,skills.sh,mode.sh,check-tiers.sh}`, `CONSTRAINTS.md` |
| Acceptance | fails today (directories + `lang node` exist); passes when deleted cleanly and `make check && make check-full` pass |
| Depends on | none (tag `archive/pre-codebase-diet` placed on master before start) |
| Must not touch | `src/quest/*`, `skills/*/SKILL.md` (except removing `skills/induct/workflows/`), `.pi/skills/` renders, `src/quest/pi_tx.ml` |

## Prose

Chesterton's fence: `skills/induct/workflows/*.js` and `extensions/bp3-pi` were built to orchestrate multi-child Muse and Pi workflow runs before `induct-inline` became the default. Across recent real quests, measured workflow-mode runs = 0. History stays preserved at `archive/pre-codebase-diet`, while `.pi/skills/`, `src/quest/pi_tx.ml`, and `pi` in `CONSTRAINTS.md`'s driven CLIs stay intact for a future `agy`-inspired Pi workflow.

Owner sign-off wording for `CONSTRAINTS.md` (2026-11-24, `/red-ink` Rounds 1 & 2): `"Drop test/pi-discovery.mjs too — remove lang node from CONSTRAINTS.md completely"` + `"Signed now — remove lang node (and pi-coding-agent) + harness extensions row from CONSTRAINTS.md"`.

## Tests

- **Known cases:** directory/file deletion assertions, `scripts/check-constraints` (3 languages), `scripts/check-gates` (updated allowlist), `test/check-tiers.sh`, `test/skills.sh` (verifies `bp3 skills install` prunes all 4 legacy `.agents/workflows/*.js` and removes empty `.agents/workflows/`), `test/mode.sh`, and `make check && make check-full` (32/32 suites).
- **Property-based:** omitted — deletion and exact gate allowlist wiring over a finite enumerated surface.
