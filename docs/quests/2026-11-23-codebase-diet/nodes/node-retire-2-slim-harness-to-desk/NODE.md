---
date: 2026-11-23
quest: ../../QUEST.md
node: retire.2
status: proposed
---

# retire.2 - slim-harness-to-desk: delete ~2,600 LOC of unused supervisor/tape/watch/link code

## TL;DR

Delete the unused workflow-supervisor subsystems from `src/quest/harness.ml` (`supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, `link`, derivation logs/caches) and their obsolete tests (`test/harness/*`, `test/link.sh`, `test/tape.sh`, `test/context.sh`), slim `src/quest/config.ml` to thresholds + desks, and keep `bp3 harness desk` (`worktree.ml`) 100% intact.

## Acceptance gates

Observed today:

```text
$ wc -l src/quest/harness.ml
    2812 src/quest/harness.ml
```

Design trace:

```text
$ wc -l src/quest/harness.ml 2>/dev/null || echo "deleted (desk routed directly in main.ml)"
# <= 100 lines or deleted altogether
$ ./bin/bp3 harness desk list           # ok:true, rc 0
$ ./bin/bp3 harness desk prepare ...    # ok:true, rc 0
$ ./bin/bp3 harness supervisor q1       # E_USAGE, rc 2 (retired)
$ ./bin/bp3 config                      # ok:true, thresholds + mode + desks
$ make check-full                       # rc 0
```

```yaml
objective: eliminate 2,600+ LOC of unused supervisor/tape/watch/link plumbing while keeping bp3 harness desk and bp3 config intact
prove by:
  - src/quest/harness.ml deleted or <= 100 LOC
  - test/worktree.sh, test/config.sh, test/g.sh, test/metrics.sh, test/completion.sh all pass
  - dune test (unit suite) and make check-full pass with zero unused-code compiler warnings
done when: dead harness subsystems and obsolete suites are removed, epoch_of_iso is preserved for Tx/Claude_tx, and make check-full passes
```

## Diagram

```text
BEFORE: src/quest/harness.ml (2,812 LOC)
  supervisor | init-check | find-tape | watch | record-init | bind-tape | backtest | link | desk

AFTER:
  bp3 harness desk <verb>  ──► Worktree.dispatch (553 LOC, unchanged behavior)
  bp3 config               ──► Config (slimmed: thresholds + mode + desks, no links/claims/by-session)
  epoch_of_iso             ──► moved to Tx / Util (still used by transcript parsers)
```

## Pseudocode

```python
# In src/quest/main.ml:
def dispatch_harness(args):
    match args:
        case ["desk", *rest]:
            return Worktree.dispatch(rest)
        case ["-h" | "--help"] | []:
            return print_harness_help()
        case _:
            usage("bp3 harness supports only: desk <derive|create|inspect|remove|prepare|check|exit|release|list>")
```

## Tables

| Field | Value |
|---|---|
| Intent | remove the single biggest god-file in `bp3` (`harness.ml`, 33.5% of OCaml LOC) now that workflow supervisors are retired |
| Lane | high-blast-radius |
| Output | `src/quest/harness.ml` (deleted or thin desk shim), `src/quest/config.ml` (slimmed), `src/quest/main.ml`, `src/quest/store.ml`, `completions/_bp3`, `completions/bp3.bash`, `test/suites.tsv`, `test/unit/dune`, removal of `test/harness/*`, `test/link.sh`, `test/tape.sh`, `test/context.sh`, `test/unit/test_mint.ml` |
| Acceptance | fails today (`harness.ml` is 2,812 LOC); passes when slimmed/deleted and `make check-full` passes |
| Depends on | `retire.1 - drop-muse-workflows-and-pi-ext` |
| Must not touch | `skills/*`, `CONSTRAINTS.md` |

## Prose

Edge cases to handle carefully:
- **`Harness.epoch_of_iso` caller:** `src/quest/claude_tx.ml:27` (or `src/quest/tx.ml` after `fast-agy-induct`) calls `Harness.epoch_of_iso`! Move `epoch_of_iso` into `Tx` (or `Util`) before deleting `harness.ml`.
- **`bp3 config` `.git/` read-only win:** notice that today `./bin/bp3 config` crashed in `agy`'s sandbox because `Config` tried to write `.git/bp3/by-session/<sid>.tmp...`! Slimming `config.ml` to drop `by-session` / `links` / `claims` fixes that sandbox crash as a direct side benefit!
- **`bp3 n` / `bp3 e` doors (Open question 1):** if the owner confirms retiring `bp3 n` and `bp3 e` alongside `link`, remove `do_e`, `do_n`, and `Store.resolved_run_id` in this same node (and clean `AGENTS.md`/`CLAUDE.md` Commands table).
- **`test/unit/test_store.ml` & `test/completion.sh`:** update any assertions that checked retired `harness supervisor|watch|link` verbs.
