---
status: landed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# codebase-diet: delete ~5,500 LOC of unused engines, unify helpers, finish Names hygiene

TL;DR
Cut ~5,700+ LOC of dead machinery (~38% of non-test code) and 11 of 36 test suites by retiring the unused Muse JS workflow scripts (`2,245` LOC), `extensions/bp3-pi` (`622` LOC), `test/pi-discovery.mjs` (dropping `lang node` completely from `CONSTRAINTS.md`), and the unused workflow-supervisor/tape/watch/backtest/link subsystems in `src/quest/harness.ml` (`~2,800` LOC) + claimed-context doors `bp3 n` / `bp3 e`, while keeping `bp3 harness desk` intact and preserving history via `archive/pre-codebase-diet`. Consolidate the 4 overlapping induct skills into 2 (`induct-inline` -> `induct`, `induct-inline-yolo` -> `induct-yolo`, promoting `docs/icebox/2026-11-23-induct-inline-becomes-induct.md`). Then extract a tiny shared `src/quest/util.ml`, delete literal dead code in `cli.ml` and `store.ml`, and promote `docs/icebox/2026-11-22-names-constants.md` so every CLI spelling lives in `src/quest/names.ml`. Unblocked now that `bp3 release` (`v0.3.0`) and `sqlite-control-plane` (`v0.4.0`) have landed and `2026-11-22-bp3-is-static-across-downstream-repo-worktrees` is canceled.

ELI5
About 43% of `bp3` is machinery built for an older Muse/Pi workflow engine that hasn't run once in the last four quests, plus copy-pasted helpers and naming leftovers from three renames. Every agent session pays context tax reading around that dead code, and every `make check-full` runs fixture suites testing it. We tag git for history, delete the unused engines cleanly, pull duplicated helpers into one tiny `Util` file, centralize CLI spellings in `Names`, and shrink the repo to the sharp core that actually runs.

## Context

Promotes two icebox entries: `docs/icebox/2026-11-22-names-constants.md` (already in [ICEBOX.md](ICEBOX.md)) and `docs/icebox/2026-11-23-induct-inline-becomes-induct.md` (folded into this quest during `/red-ink` Round 1, 2026-11-24; copied verbatim at approval). Unblocked now that `2026-11-23-quest-promote-release` (`v0.3.0`), `2026-11-23-sqlite-control-plane` (`v0.4.0`), and `91d27b1` have landed and `2026-11-22-bp3-is-static-across-downstream-repo-worktrees` is canceled (`1262fb1`). Runs before `docs/icebox/2026-11-24-split-src-quest.md`, `docs/icebox/2026-11-23-single-cli.md`, and `docs/icebox/2026-11-24-central-desks-dir.md`.

Measured ground (re-audited 2026-11-24 on `HEAD` `1262fb1`, post-`v0.4.0`):

| Fact | Source |
|---|---|
| Live OCaml + JS/TS non-test LOC: `src/quest/` + `src/warden/` + `src/db/` + `src/repo/` + `src/ticket/` + `skills/induct/workflows/*.js` + `extensions/bp3-pi/` = **15,119 LOC** (plus skills/bin/scripts); **36** suites in `test/suites.tsv` | `wc -l`, `test/suites.tsv` (2026-11-24) |
| `src/quest/harness.ml` is **2,812 LOC** mixing 9 subsystems (`supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, `link`, lifecycle cache) built for workflow runs that had **zero measured runs**; only non-`main.ml` caller is `src/quest/tx.ml:45` (`Harness.epoch_of_iso`) | `wc -l`, `rg "Harness\." src/` (2026-11-24) |
| `skills/induct/workflows/*.js` is **2,245 LOC** (`induct-grade.js` alone is 1,022 LOC); `extensions/bp3-pi/` is **622 LOC**; `test/pi-discovery.mjs` (58 LOC, opt-in/skipped) is the ONLY remaining JS file in the repo | `find` + `wc -l` (2026-11-24) |
| **11 of 36** suites in `test/suites.tsv` test dead workflow/Pi/supervisor/link surfaces (`bp3-pi`, `js-unit`, `transcripts`, `induct`, `harness-cli`, `harness-fold`, `harness-evidence`, `harness-backtest`, `link`, `context`, `tape`); `js-unit` is the ONLY `unit`-tier row in `test/suites.tsv` | `test/suites.tsv` (2026-11-24) |
| Literal dead code: `src/quest/cli.ml:40-47` (`let has = ... in ignore has;`), `src/quest/store.ml:115-118` (`if contains_sub ... then grade_required else grade_required`) | read directly (2026-11-23) |
| Duplicated primitives: `contains_sub` (`store.ml`, `config.ml`), `ensure_dir`/`mkdir_p` (`harness.ml`, `config.ml`, `worktree.ml`, `run_suites.ml`), multiple Yojson string/member getters, atomic writers | `rg` audit (2026-11-23) |
| Naming drift: `worktree` in `worktree.ml` vs `desk` in docs; `e` variable names for nodes (old `exp`) across `main.ml`/`store.ml`; `bp3 g` header comment in `gitx.ml:1`; `names.ml` holds only 8 lines while `E_*` codes stay raw literals | `rg` audit (2026-11-23) |
| 4 overlapping induct skills (`induct`, `induct-yolo`, `induct-inline`, `induct-inline-yolo`) where `induct`/`induct-yolo` describe the dead Muse JS workflow engine | `ls skills/` (2026-11-24) |

Owner Shape decisions settled (2026-11-24, `/red-ink` Round 1):
1. Keep all 5 nodes in `codebase-diet` (`retire.1`, `retire.2`, `clean.1`, `clean.2`, `skills.1`).
2. Fold & promote `docs/icebox/2026-11-23-induct-inline-becomes-induct.md`: rename `induct-inline` -> `induct` and `induct-inline-yolo` -> `induct-yolo`, deleting the legacy conductor skills.
3. Retire `bp3 n` and `bp3 e` claimed-context doors alongside `harness link`.
4. Drop `test/pi-discovery.mjs` too and remove `lang node` completely from `CONSTRAINTS.md` (alongside `extensions/bp3-pi` and workflow scripts).

## Terms

| Term | Meaning |
|---|---|
| `archive/pre-codebase-diet` | annotated git tag placed before promotion (Chesterton's fence: full recoverable snapshot of Muse workflows, `bp3-pi`, and `harness supervisor`) |
| `Util` | new shared module `src/quest/util.ml`: `contains_sub`, `strip_prefix`, `mkdir_p`, `write_file_atomic`, and total Yojson field helpers (`member`, `get_str`, `get_int`, `get_bool`) |
| `Names` | expanded `src/quest/names.ml`: single source of truth for every CLI door, verb, edge, state, flag, and `E_*` error code; `Store.reserved_slugs` derived directly from it |
| `desk` | canonical spelling for isolated quest/grade git worktrees (`bp3 harness desk ...`; `.bp3/worktrees` path kept or migrated cleanly without breaking existing desks) |

## Inputs

| Input | Source |
|---|---|
| existing OCaml engine (`src/quest/`, `src/warden/`, `src/db/`, `src/repo/`, `src/ticket/`), skills, tests, `Makefile`, `test/suites.tsv`, `CONSTRAINTS.md` | repo at post-`v0.4.0` HEAD (`1262fb1`+) |
| owner `CONSTRAINTS.md` sign-off | settled in `/red-ink` Round 2 (2026-11-24): removes `lang node` (`@earendil-works/pi-coding-agent`) and `harness extensions` (`extensions/bp3-pi`, workflow scripts) |
| surviving env vars | `BP3_RUN_ID` (**kept** — read by `store.ml`, `hooks.ml`, `ticket_cli.ml`), `BP3_DECIDER`, `BP3_ROOT`, `BP3_TARGET`, `BP3_COMPLETIONS_DIR`, `BP3_SKILLS_DIR`, `BP3_Q_BIN`, `BP3_DB`, `PREFIX`, `BP3_NO_AUTO_SYNC` |
| retired inputs | `MUSE_SESSION_ID` / `MUSE_THREAD_ID` / `BP3_SESSION_ID` claim resolution (`config.ml`), `bp3 n` / `bp3 e` argv, `bp3 harness <non-desk>` argv, `scripts/shell-files --node`, and `.git/bp3/{runs,links,claims,by-session}` auto-creation on `bp3 config` read |

## Outputs

| Output | Shape |
|---|---|
| deleted dead surfaces | `skills/induct/workflows/`, `.agents/workflows/`, `extensions/bp3-pi/`, `test/pi-discovery.mjs`, dead `harness.ml` subsystems, `bp3 n` / `bp3 e` doors, and 11 obsolete fixture/unit suites removed cleanly |
| retired CLI contract | `bp3 n`, `bp3 e`, and `bp3 harness <non-desk>` refuse cleanly with `E_USAGE` (exit 2), naming `bp3 harness desk` for harness calls; `bp3 config` drops `links`/`claims`/`by-session` and stops writing `.git/bp3/by-session/*` |
| `Makefile` & `scripts/check-gates` | `make lint` drops the `node --check` step (`scripts/shell-files --node` retired); `make check` = `lint` + `dune build` + `dune test` (drops `./scripts/run-suites --tier unit` now that `js-unit` is gone); `make check-full` = `check` + `./scripts/run-suites`; `scripts/check-gates` and `test/check-tiers.sh` updated in lockstep |
| `CONSTRAINTS.md` | removes `lang node` line (and `@earendil-works/pi-coding-agent`) and the `harness extensions` row from `Surfaces`, backed by the owner's 2026-11-24 sign-off row |
| downstream `bp3 skills install` pruning | moves all 4 workflow names (`node-loop`, `induct-grade`, `induct-land`, `induct-node`) into `RETIRED_WORKFLOWS` (auto-prunes `.agents/workflows/*.js` and removes empty `.agents/workflows/` dir); `prune_stale` auto-removes `induct-inline` and `induct-inline-yolo` renders when dropped from `CORE_SKILLS` |
| `src/quest/util.ml` | single home for string/fs/atomic-write/time/JSON helpers; zero duplicate copies across `src/quest/` |
| `src/quest/names.ml` | single home for every CLI verb/door/edge/state/flag/`E_*` code + test failing on rogue literals |
| consolidated skills | 2 sharp conducting skills (`induct` + `induct-yolo` promoted from `induct-inline` / `induct-inline-yolo`) + synced renders across `.agents/`, `.claude/`, `.pi/` |
| faster `make check-full` | 11 dead suites removed (36 -> 25 suites) -> faster gate wall time |

## Acceptance gates

Observed today (2026-11-24, `HEAD` `1262fb1`):

```text
$ wc -l src/quest/harness.ml skills/induct/workflows/*.js extensions/bp3-pi/index.ts extensions/bp3-pi/src/*.ts | tail -n 1
    5679 total
$ ls test/pi-discovery.mjs skills/ | grep -E "pi-discovery|induct"
induct
induct-inline
induct-inline-yolo
induct-yolo
test/pi-discovery.mjs
$ grep -c '^[^#]' test/suites.tsv
36
$ rg -n "ignore has" src/quest/cli.ml
47:    ignore has;
$ rg -n "then grade_required else grade_required" src/quest/store.ml
118:      grade_required else grade_required in
$ wc -l src/quest/names.ml
       8 src/quest/names.ml
```

Design trace (after quest lands):

```text
retire.1  ls skills/induct/workflows extensions/bp3-pi .agents/workflows test/pi-discovery.mjs -> No such file or directory
          CONSTRAINTS.md drops `lang node` and `harness extensions` row with owner 2026-11-24 sign-off row
          Makefile drops `node --check` and `./scripts/run-suites --tier unit`; check-gates + test/check-tiers.sh green
          bin/bp3 skills install prunes all 4 retired .agents/workflows/*.js files (+ empty dir)
          make check-full rc 0 (32 suites)
retire.2  src/quest/harness.ml deleted (0 LOC); main.ml routes `bp3 harness desk` directly to Worktree
          bp3 harness supervisor, bp3 n, bp3 e -> E_USAGE (exit 2)
          bp3 config ~60 LOC strictly read-only (never writes .git/bp3/ on read); render.ml emits setup: [] (W_SETUP_SLOW dropped)
          Harness.epoch_of_iso moved into Tx; 7 dead harness/link/context/tape suites deleted (25 suites left)
          make check-full rc 0
clean.1   src/quest/util.ml exists (~90 LOC, stdlib+unix+yojson only); zero duplicate contains_sub / strip_prefix / ensure_dir / mkdir_p / write_file_atomic / epoch_of_iso
          cli.ml:ignore has and store.ml:no-op gone; test/unit/test_util.ml + make check-full rc 0
clean.2   src/quest/names.ml holds all doors, verbs, edges, states, flags, E_* codes for src/quest/*.ml
          Store.reserved_slugs derived from Names (+ "warden", minus retired supervisor/watch/backtest/init-check/find-tape/n/e)
          test/unit/test_names.ml fails if any raw `err "E_` literal appears in src/quest/*.ml outside names.ml
          gitx.ml:1 says "bp3 q"; internal e -> node and worktree -> desk comment hygiene clean; make check-full rc 0
skills.1  skills/induct/SKILL.md and skills/induct-yolo/SKILL.md promoted from induct-inline*; skills/induct-inline* deleted
          zero dead Muse workflow or induct-inline prose in skills/, AGENTS.md, CLAUDE.md, scripts/check-retired-terms.sh
          all renders synced (.agents/, .claude/, .pi/) and stale induct-inline* pruned; test/skills.sh + test/mode.sh + make check-full rc 0
all       ~5,700+ LOC deleted, 25/25 suites green (down from 36), historical pre-rename quests still fold cleanly (`bp3 q r 2026-11-05-bp3-mvp` -> goal_fin)
```

## Goal and why

Shrink `bp3` to the sharp, readable core that actually runs every day. Deleting ~5,500 lines of unused Muse/Pi workflow machinery reduces agent context tax on every session, removes dead fixture suites from `make check-full`, eliminates copy-paste helper drift, and prepares a clean foundation for thawing `2026-11-23-single-cli.md`.

## Success picture

- Non-test codebase drops by >= 4,500 LOC (from ~14,073 to < 9,500 LOC), with `src/quest/harness.ml` retired down to `desk` only.
- `make check-full` runs measurably faster (recorded before vs after in `QUEST.md` build notes) with zero skipped assertions on surviving features.
- Zero duplicated helper primitives across `src/quest/`, zero dead no-op lines, and every CLI verb/edge/state/error code centralized in `src/quest/names.ml`.
- All surviving skills describe only the real inline + `agy` workflow, with zero dead Muse workflow instructions.

## Scope

| In | Out |
|---|---|
| Deleting `skills/induct/workflows/*.js`, `.agents/workflows/`, `extensions/bp3-pi/`, `test/pi-discovery.mjs`, `lang node` in `CONSTRAINTS.md`, and their obsolete tests (`retire.1`) | Merging `bin/bp3` into a single OCaml binary (`docs/icebox/2026-11-23-single-cli.md`, separate quest) |
| Deleting unused `harness.ml` subsystems (`supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, `link`) + retiring `bp3 n` / `bp3 e` while keeping `harness desk` (`retire.2`) | Splitting `src/quest/` into domain libraries (`docs/icebox/2026-11-24-split-src-quest.md`, next quest) or moving desks to `~/.bp3/desks/` (`docs/icebox/2026-11-24-central-desks-dir.md`) |
| `src/quest/util.ml`, removing dead code in `cli.ml`/`store.ml`, unifying duplicated helpers (`clean.1`) | Rewriting stored git ledger history (read-side `Layout.legacy_*` folds stay intact so old quests still read!) |
| Promoting `2026-11-22-names-constants.md` (`names.ml`, `reserved_slugs`, `worktree` -> `desk` internal hygiene, `e` -> `node` var cleanup) (`clean.2`) | Changing FSM semantics, `metrics.jsonl` schema, `warden`, `release`, or `sqlite-control-plane` behavior |
| Promoting `2026-11-23-induct-inline-becomes-induct.md`: renaming `induct-inline` -> `induct` and `induct-inline-yolo` -> `induct-yolo`, deleting legacy conductor skills (`skills.1`) | Re-adding a future `agy`-inspired Pi workflow (`.pi/skills/` rendering, `pi_tx.ml` metrics parsing, and `pi` as a driven harness CLI stay intact; only the old TS `extensions/bp3-pi/` dies) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **Removes** `lang node` (plus `@earendil-works/pi-coding-agent`) and the `harness extensions` row (`extensions/bp3-pi`, workflow scripts) from `CONSTRAINTS.md`. **Owner signed off during `/red-ink` Round 2 (2026-11-24):** `"Signed now — remove lang node (and pi-coding-agent) + harness extensions row from CONSTRAINTS.md"` (plus Round 1: `"Drop test/pi-discovery.mjs too — remove lang node from CONSTRAINTS.md completely"`).
- **Common-sense pass (`CONTEXT.md`):**
  - YAGNI (`CONTEXT.md:78`): building is cheap, carrying unused machinery costs context and CI time on every future quest.
  - Chesterton's fence (`CONTEXT.md:82`): every deleted subsystem documents why it existed (`Muse JS workflows`, `bp3-pi`, `supervisor` had zero measured runs once `induct-inline` became default) and stays recoverable at tag `archive/pre-codebase-diet`.
  - Gall's law (`CONTEXT.md:80`): keep the simple working engine (`bp3 q` + `desk` + `brief` + `metrics` + `warden`) lean instead of dragging an unused distributed supervisor.

## Human touchpoints

| When | Owner |
|---|---|
| Confirm `CONSTRAINTS.md` removal wording + settle Open questions 1-3 (`bp3 n`/`bp3 e`, skill naming, `pi-discovery.mjs`) | owner |
| Approve frame (after `bp3-is-static` lands) | owner |
| Tag `archive/pre-codebase-diet` + promote (`goal_fin`) | owner |

## Nodes

### Milestone: retire

| Node | TL;DR |
|---|---|
| [retire.1 - drop-muse-workflows-and-pi-ext](nodes/node-retire-1-drop-muse-workflows-and-pi-ext/NODE.md) | delete `skills/induct/workflows/*.js`, `.agents/workflows/`, `extensions/bp3-pi/`, and their tests; update `Makefile`, `suites.tsv`, `bin/bp3`, `CONSTRAINTS.md` |
| [retire.2 - slim-harness-to-desk](nodes/node-retire-2-slim-harness-to-desk/NODE.md) | delete dead `harness.ml` supervisor/tape/watch/backtest/link subsystems (~2,600 LOC) and obsolete tests; keep `bp3 harness desk` + lean `config.ml` |

### Milestone: clean

| Node | TL;DR |
|---|---|
| [clean.1 - util-and-dead-code](nodes/node-clean-1-util-and-dead-code/NODE.md) | extract `src/quest/util.ml` (dedup string/fs/atomic/JSON helpers) and delete dead code in `cli.ml` and `store.ml` |
| [clean.2 - names-and-desk-hygiene](nodes/node-clean-2-names-and-desk-hygiene/NODE.md) | promote `names-constants`: move all CLI doors/verbs/edges/states/flags/`E_*` codes into `src/quest/names.ml`, derive `reserved_slugs`, clean `worktree`/`e`/`bp3 g` residue |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - consolidate-induct-skills](nodes/node-skills-1-consolidate-induct-skills/NODE.md) | remove dead Muse workflow prose and consolidate the 4 overlapping `induct*` skills into 2 crisp skills (+ renders, `AGENTS.md`/`CLAUDE.md`, skill node) |

## Scorecard

| Row | Baseline (2026-11-24, `1262fb1`) | Target | Read from |
|---|---|---|---|
| deleted dead surface LOC | 5,679 LOC (`harness.ml` + workflows + `bp3-pi`) + 58L `pi-discovery.mjs` + ~350L `config.ml` | **0 LOC** (all deleted) | `wc -l` |
| `src/quest/harness.ml` | 2,812 LOC | **deleted (0 LOC)** (`main.ml` -> `Worktree`) | `ls` / `wc -l` |
| `test/suites.tsv` suite count | 36 suites | **25 suites** (11 dead suites removed) | `grep -c '^[^#]' test/suites.tsv` |
| `CONSTRAINTS.md` languages | 4 (`ocaml`, `bash`, `zsh`, `node`) | **3** (`ocaml`, `bash`, `zsh`; `node` gone) | `scripts/check-constraints` |
| `src/quest/names.ml` coverage (`src/quest/*.ml`) | 3 constants | **100%** of `src/quest/` doors/verbs/edges/states/flags/`E_*` | `test_names.ml` literal guard |
| conducting skills | 4 (`induct`, `induct-yolo`, `induct-inline`, `induct-inline-yolo`) | **2** (`induct`, `induct-yolo`) | `ls skills/` |

## Risks and red chair

- **Strongest attack (breaking hidden callers of `harness.ml`, `bp3 n`/`bp3 e`, or `BP3_RUN_ID`):**
  - **Settled:**
    1. Only non-`main.ml` caller of `Harness` is `src/quest/tx.ml:45` (`Harness.epoch_of_iso`) -> moved into `Tx` in `retire.2`, then `Util` in `clean.1`.
    2. `BP3_RUN_ID` stays intact (`store.ml`, `hooks.ml`, `ticket_cli.ml`); only `Store.resolved_run_id`, `W_CONTEXT_*`, and `MUSE_SESSION_ID`/`BP3_SESSION_ID` claim lookup retire.
    3. `bp3 n` and `bp3 e` retire cleanly behind `E_USAGE` (exit 2).
- **Second attack (gate breakage when `js-unit` and last JS file disappear):**
  - **Settled:** `retire.1` removes `node --check` from `Makefile` (`scripts/shell-files --node`), drops `./scripts/run-suites --tier unit` from `make check` (`check` = `lint` + `dune build` + `dune test`), and updates `scripts/check-gates` + `test/check-tiers.sh` in lockstep.
- **Third attack (breaking historical quest reads):**
  - **Settled:** All read-side `Layout.legacy_*` and `Store.fold_edge`/`fold_state_name` mappings stay untouched; `test/unit/test_store.ml` (exp/graph/quest samples) stays green throughout.
- **Fourth attack (breaking `bp3_db`/`bp3_repo`/`bp3_ticket` dune dependency direction in `clean.2`):**
  - **Settled:** `src/quest/names.ml` and `test_names.ml` scope strictly to `src/quest/*.ml` (`src/db`, `src/repo`, `src/ticket` are lower-level libs and join `bp3_core` later in `split-src-quest`).
- **Closing Red Chair caller audit (2026-11-24, verified by `rg` on `HEAD` `1262fb1`):**
  - `test/unit/test_clock.ml:41` calls `Harness.compact_ts` -> update in `retire.2` to test `Clock.with_fixed` against `Gitx.now_iso` (or drop the `Harness` call).
  - `test/unit/test_main.ml:98` calls `Config.valid_index_key` -> delete that `by-session` assertion in `retire.2` (keep `Config.thresholds_of_json` at lines 61-62).
  - `test/g.sh:51-52,701` assert `bp3 n r` (`E_NO_CONTEXT`) and `bp3 e block` -> update in `retire.2` to assert `E_USAGE` retirement and test major-ahead via `bp3 q`.
  - `test/mode.sh:89` & `test/skills.sh:93-97,119,142-143,162,261-414` assert the 4 `.agents/workflows/*.js` files (`retire.1`) and `induct-inline*` / `.pi/settings.json` skill exclusion arrays (`skills.1`) -> update in lockstep in `retire.1` and `skills.1`.
  - `scripts/check-constraints` (`libs node`) & `scripts/red-first:104` (`[ "$s" != "js-unit" ]`) -> clean up in `retire.1` so `set -e` never trips when `lang node` is absent.

## Open questions

*(All framing open questions settled during `/red-ink` Rounds 1–3 on 2026-11-24. Zero open questions remaining.)*

## Node diagram

```text
(tag archive/pre-codebase-diet before Wave 1)

Wave 1: retire.1 (drop Muse JS, bp3-pi, pi-discovery.mjs, lang node, check-gates)
           │
Wave 2: retire.2 (delete harness.ml, retire bp3 n/e, slim config.ml, setup:[] in render.ml)
           │
           ├─────────────────────────────────────────────────┐
Wave 3: clean.1 (src/quest/util.ml + dead code)        skills.1 (induct-inline -> induct,
           │                                                     induct-inline-yolo -> induct-yolo,
Wave 4: clean.2 (src/quest/names.ml + reserved_slugs +           renders, docs, retired-terms)
                 warden + test_names.ml + desk hygiene)
```

## Quest-level functional tests

End-to-end functional checks proving all 5 nodes compose cleanly (run before `goal_fin`):

1. **Happy path — full repo gate & clean CLI surface (functional fixture + real repo):**
   - Starting state: quest tip after all 5 nodes land (`make check-full`).
   - Action: run `make check`, `make check-full`, `./bin/bp3 harness desk list`, `./bin/bp3 q r 2026-11-05-bp3-mvp`, and `./bin/bp3 config`.
   - Observable result: `make check` runs `lint` + `dune build` + `dune test` cleanly (exit 0, 3 languages in `check-constraints`); `make check-full` passes all 25/25 suites; `bp3 config` succeeds read-only without creating `.git/bp3/` dirs; `2026-11-05-bp3-mvp` folds to `goal_fin`.
2. **Refusal path — retired surfaces refuse with state unchanged (functional fixture):**
   - Starting state: clean fixture git repo with an active quest.
   - Action: invoke `bp3 harness supervisor q1`, `bp3 n r`, `bp3 e handoff --commit HEAD --reason "x"`.
   - Observable result: every call exits 2 with `E_USAGE` JSON; `git status --short` and `bp3 q r q1` ledger are unchanged.
3. **Downstream migration & pruning path (functional fixture simulating `~/m/predictor`):**
   - Starting state: host fixture repo containing legacy `.agents/workflows/{node-loop,induct-grade,induct-land,induct-node}.js` and rendered `.claude/skills/induct-inline/SKILL.md` + `.claude/skills/induct-inline-yolo/SKILL.md` with `<!-- GENERATED ... -->` headers.
   - Action: run `BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=all` followed by `./bin/bp3 skills check`.
   - Observable result: all 4 legacy workflow files and empty `.agents/workflows/` dir are pruned; `induct-inline` / `induct-inline-yolo` renders are pruned; `induct` / `induct-yolo` renders are written with zero dead workflow prose; `bp3 skills check` returns `{"ok":true,...}`.
4. **Chesterton's fence & literal-guard invariants (real repo):**
   - Starting state: quest tip + annotated tag `archive/pre-codebase-diet` on pre-diet `master`.
   - Action: `git rev-parse archive/pre-codebase-diet:src/quest/harness.ml` and `dune test` (`test_util.ml`, `test_names.ml`, `test_store.ml`).
   - Observable result: archived `harness.ml` resolves cleanly from tag; `test_names.ml` confirms 0 raw `err "E_..."` literals in `src/quest/*.ml` outside `names.ml` and `Store.reserved_slugs` includes `"warden"` and every surviving door/verb.
