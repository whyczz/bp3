---
date: 2026-11-23
quest: ../../QUEST.md
node: retire.1
status: proposed
---

# retire.1 - drop-muse-workflows-and-pi-ext: remove 2,867+ LOC of unused JS/TS workflow engines

## TL;DR

Delete `skills/induct/workflows/*.js` (2,245 LOC), `.agents/workflows/*.js`, `extensions/bp3-pi/` (622 LOC), and their obsolete test suites (`test/induct*.mjs`, `test/node-loop.test.mjs`, `test/induct.sh`, `test/js-unit.sh`, `test/transcripts.sh`, `test/fake-bp3/`, `scripts/record-transcripts`). Update `bin/bp3` to prune all retired `.agents/workflows/*.js` renders, clean `Makefile` and `test/suites.tsv`, and update `CONSTRAINTS.md` with the owner's removal sign-off row.

## Acceptance gates

Observed today:

```text
$ ls skills/induct/workflows/ extensions/bp3-pi/
skills/induct/workflows/: induct-grade.js  induct-land.js  induct-node.js  node-loop.js
extensions/bp3-pi/: index.ts  package.json  README.md  roles  src  test
```

Design trace:

```text
$ ls skills/induct/workflows extensions/bp3-pi .agents/workflows 2>&1
No such file or directory
$ BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install
  - prunes any leftover .agents/workflows/{node-loop,induct-grade,induct-land,induct-node}.js cleanly
$ make check-full
  - rc 0, zero missing suite errors, faster wall time (recorded in build notes)
```

```yaml
objective: delete the unused Muse JS workflows and bp3-pi extension cleanly with zero dangling references or failing checks
prove by:
  - test ! -e skills/induct/workflows && test ! -e extensions/bp3-pi && test ! -e .agents/workflows
  - ./scripts/check-constraints && ./scripts/check-gates
  - test/skills.sh (verifies bp3 skills install prunes retired workflow renders)
  - make check-full
done when: all deleted directories are gone, CONSTRAINTS.md carries the owner removal sign-off row, and make check-full passes
```

## Diagram

```text
DELETE:
  skills/induct/workflows/*.js   (2,245 LOC)
  .agents/workflows/*.js         (generated copies)
  extensions/bp3-pi/**           (622 LOC + tests)
  test/induct*, test/node-loop*, test/js-unit.sh, test/transcripts.sh, test/fake-bp3/, scripts/record-transcripts

UPDATE:
  bin/bp3          (move WORKFLOW_NAMES into RETIRED_WORKFLOWS; skills check verifies SKILL.md renders only)
  Makefile         (drop dead JS lint loop if no node files remain, or keep for pi-discovery.mjs)
  test/suites.tsv  (remove bp3-pi, js-unit, transcripts, induct rows)
  CONSTRAINTS.md   (owner sign-off row removing @earendil-works/pi-coding-agent and harness extensions surface)
```

## Pseudocode

```python
def retire_js_engines():
    assert git_tag_planned("archive/pre-codebase-diet")
    delete_trees([
        "skills/induct/workflows",
        ".agents/workflows",
        "extensions/bp3-pi",
        "test/fake-bp3",
        "scripts/record-transcripts",
        "test/induct.sh", "test/js-unit.sh", "test/transcripts.sh",
        "test/induct-*.test.mjs", "test/node-loop.test.mjs",
    ])
    update_bin_bp3_prune_all_workflows()
    update_suites_tsv_and_makefile()
    update_constraints_with_owner_signoff()
```

## Tables

| Field | Value |
|---|---|
| Intent | remove 2,867 LOC of dead Muse JS workflows and Pi extension + their maintenance/CI tax |
| Lane | high-blast-radius |
| Output | deletions above + updated `bin/bp3`, `Makefile`, `scripts/check-gates`, `scripts/shell-files`, `scripts/check-retired-terms.sh`, `test/suites.tsv`, `test/skills.sh`, `test/check-tiers.sh`, `CONSTRAINTS.md` |
| Acceptance | fails today (directories exist); passes when deleted cleanly and `make check-full` passes |
| Depends on | none (after `2026-11-22-bp3-is-static` lands) |
| Must not touch | `src/quest/*`, `skills/*/SKILL.md` (except removing deleted workflow files) |

## Prose

Chesterton's fence: `skills/induct/workflows/*.js` and `extensions/bp3-pi` were built to orchestrate multi-child Muse and Pi workflow runs before `induct-inline` became the default. Across the last 4 quests, measured workflow-mode runs = 0. History stays preserved via the `archive/pre-codebase-diet` tag.

Edge cases:
- **`scripts/check-gates` and `test/check-tiers.sh`:** `test/suites.tsv` must stay non-empty in the `unit` tier OR `Makefile` `check` target must rely on `dune test` cleanly if `js-unit` was the only `unit` tier row in `test/suites.tsv`! Verify `run-suites --tier unit` handles 0 rows cleanly (or updates `check`/`check-gates` together). Great catch to check during build!
- **`scripts/check-retired-terms.sh`:** remove `extensions` and `.agents/workflows` from its live-surface `scope` list so `git grep` doesn't complain on absent paths.
- **`bin/bp3` `skills check`:** once `WORKFLOW_NAMES` is empty, `skills check` should check SKILL.md render freshness (from `bp3-is-static`) cleanly without looping over empty workflow names.
