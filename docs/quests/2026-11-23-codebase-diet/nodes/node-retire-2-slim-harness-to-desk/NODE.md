---
date: 2026-11-23
quest: ../../QUEST.md
node: retire.2
status: active
---

# retire.2 - slim-harness-to-desk: delete `harness.ml`, retire `bp3 n`/`e`, slim `config.ml`

## TL;DR

Delete `src/quest/harness.ml` completely (2,812 -> 0 LOC), route `bp3 harness desk` directly in `src/quest/main.ml` -> `Worktree`, retire `bp3 n` / `bp3 e` and non-`desk` `bp3 harness` subcommands with plain `E_USAGE` (exit 2), move `Harness.epoch_of_iso` into `src/quest/tx.ml`, keep `BP3_RUN_ID` intact (`store.ml`, `hooks.ml`, `ticket_cli.ml`) while dropping `Store.resolved_run_id` / `W_CONTEXT_*`, slim `src/quest/config.ml` to ~60-line strictly read-only (`mode`, `thresholds`, `desks`; never writes `.git/bp3/` on read), simplify `src/quest/render.ml` (`setup: []`, drop dead `W_SETUP_SLOW`), delete 7 obsolete suites (`test/harness/*`, `test/link.sh`, `test/tape.sh`, `test/context.sh`, `test/unit/test_mint.ml`), and update affected assertions in `test/unit/test_clock.ml:41`, `test/unit/test_main.ml:98`, `test/g.sh:51-52,701`, `test/config.sh`, and `test/completion.sh`.

## Acceptance gates

Observed today (2026-11-24):

```text
$ wc -l src/quest/harness.ml src/quest/config.ml
    2812 src/quest/harness.ml
     411 src/quest/config.ml
```

Design trace:

```text
$ test ! -e src/quest/harness.ml && echo "deleted"
deleted
$ wc -l src/quest/config.ml
# ~60 lines (read-only: mode, thresholds, desks)
$ ./bin/bp3 harness desk list           # ok:true, rc 0
$ ./bin/bp3 harness supervisor q1       # E_USAGE, rc 2
$ ./bin/bp3 n r                         # E_USAGE, rc 2
$ ./bin/bp3 e handoff --commit HEAD     # E_USAGE, rc 2
$ ./bin/bp3 config                      # ok:true, read-only (does not create .git/bp3/)
$ make check && make check-full         # rc 0 (25/25 suites)
```

```yaml
objective: delete harness.ml (0 LOC), retire bp3 n/e and dead harness subcommands behind E_USAGE, slim config.ml to strictly read-only, and keep bp3 harness desk and BP3_RUN_ID intact
prove by:
  - test ! -e src/quest/harness.ml
  - bp3 harness supervisor, bp3 n r, and bp3 e handoff all exit 2 with E_USAGE
  - bp3 config succeeds without creating .git/bp3/ directories
  - test/worktree.sh, test/config.sh, test/g.sh, test/metrics.sh, test/completion.sh all pass
  - dune test and make check-full pass (25/25 suites) with zero unused-code compiler warnings
done when: harness.ml and 7 obsolete suites are deleted, epoch_of_iso lives in Tx, hidden unit/g.sh callers are updated, and make check-full passes
```

## Diagram

```text
BEFORE: src/quest/harness.ml (2,812 LOC) + src/quest/config.ml (411 LOC)
  supervisor | init-check | find-tape | watch | record-init | bind-tape | backtest | link | desk
  bp3 n / bp3 e (claimed context doors) + .git/bp3/{runs,links,claims,by-session}

AFTER:
  bp3 harness desk <verb>  ──► main.ml -> Worktree.dispatch (unchanged behavior)
  bp3 harness <other>      ──► E_USAGE (exit 2, names `desk`)
  bp3 n / bp3 e            ──► E_USAGE (exit 2, dropped from bin/bp3 + main.ml)
  bp3 config               ──► Config (~60L, strictly read-only: mode + thresholds + desks)
  render.ml setup          ──► setup: [] (W_SETUP_SLOW scan dropped)
  epoch_of_iso             ──► moved to src/quest/tx.ml (still used by transcript parsers)
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
| Intent | remove the single biggest god-file in `bp3` (`harness.ml`, 2,812 LOC) + 350L of dead `config.ml` link/claim state |
| Lane | high-blast-radius |
| Output | delete `src/quest/harness.ml`, `test/harness/*`, `test/link.sh`, `test/tape.sh`, `test/context.sh`, `test/unit/test_mint.ml`; update `src/quest/{config.ml,render.ml,main.ml,store.ml,tx.ml}`, `bin/bp3`, `completions/{_bp3,bp3.bash}`, `test/suites.tsv`, `test/unit/{dune,test_clock.ml,test_main.ml}`, `test/{g.sh,config.sh,completion.sh}` |
| Acceptance | fails today (`harness.ml` is 2,812 LOC, `bp3 n` returns `E_NO_CONTEXT`); passes when deleted/slimmed and `make check-full` passes |
| Depends on | `retire.1 - drop-muse-workflows-and-pi-ext` |
| Must not touch | `skills/*`, `CONSTRAINTS.md`, `Layout.legacy_*` read folds, `BP3_RUN_ID` in `store.ml`/`hooks.ml`/`ticket_cli.ml` |

## Prose

Closing Red Chair callers verified on `HEAD` `1262fb1` (must update in this commit):
- `src/quest/tx.ml:45` calls `Harness.epoch_of_iso` -> move `epoch_of_iso` into `src/quest/tx.ml`.
- `test/unit/test_clock.ml:41` calls `Harness.compact_ts` -> replace with `Gitx.now_iso` (or drop the `Harness` call).
- `test/unit/test_main.ml:98` calls `Config.valid_index_key` -> delete that `by-session` test (keep `Config.thresholds_of_json` at lines 61–62).
- `test/g.sh:51-52,701` test `bp3 n r` (`E_NO_CONTEXT`) and `MUSE_SESSION_ID=sess-vf bp3 e block` -> update lines 51–52 to assert `E_USAGE` retirement and test major-ahead refusal via `bp3 q`.
- `bp3 config` strictly read-only: never writes `.git/bp3/` on read, fixing the read-only `.git/` sandbox crash as a direct win.

## Tests

- **Known cases:** `harness.ml` absent, `bp3 harness supervisor` / `bp3 n r` / `bp3 e` return `E_USAGE` (exit 2), read-only `bp3 config` on read-only `.git/`, `test/worktree.sh`, `test/config.sh`, `test/g.sh`, `test/metrics.sh`, `test/completion.sh`, `dune test`, and `make check-full` (25/25 suites).
- **Property-based:** omitted — deletion and finite dispatch table refactoring; every retired verb and surviving desk verb is enumerated.
