---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# codebase-diet: delete ~5,500 LOC of unused engines, unify helpers, finish Names hygiene

TL;DR
Cut nearly half of `bp3`'s non-test codebase (~5,500+ LOC) by retiring the unused Muse JS workflow scripts (`2,245` LOC), `extensions/bp3-pi` (`622` LOC), and the unused workflow-supervisor/tape/watch/backtest/link subsystems in `src/quest/harness.ml` (`~2,600` LOC) while keeping `bp3 harness desk` intact and preserving history via a git tag (`archive/pre-codebase-diet`). Then extract a tiny shared `src/quest/util.ml` for duplicated primitives, delete literal dead code in `cli.ml` and `store.ml`, promote `docs/icebox/2026-11-22-names-constants.md` so every CLI spelling lives in `src/quest/names.ml`, and consolidate the overlapping `induct` skills. Sequenced after `2026-11-22-bp3-is-static-across-downstream-repo-worktrees`.

ELI5
About 43% of `bp3` is machinery built for an older Muse/Pi workflow engine that hasn't run once in the last four quests, plus copy-pasted helpers and naming leftovers from three renames. Every agent session pays context tax reading around that dead code, and every `make check-full` runs fixture suites testing it. We tag git for history, delete the unused engines cleanly, pull duplicated helpers into one tiny `Util` file, centralize CLI spellings in `Names`, and shrink the repo to the sharp core that actually runs.

## Context

Promotes `docs/icebox/2026-11-22-names-constants.md` (copied verbatim to [ICEBOX.md](ICEBOX.md)). Sequenced **after** `docs/quests/2026-11-22-bp3-is-static-across-downstream-repo-worktrees/` (so install/release versioning is live before removing deprecated surfaces, and `docs/icebox/2026-11-23-single-cli.md` can thaw cleanly right alongside or right after).

Measured ground (audited 2026-11-23):

| Fact | Source |
|---|---|
| Total non-test LOC: **14,073** (`8,388` OCaml + `3,904` skills/workflows + `1,781` bin/extensions/scripts) | `wc -l` audit (2026-11-23) |
| `src/quest/harness.ml` is **2,812 LOC** (**33.5%** of all OCaml) mixing 9 subsystems (`supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, `link`, lifecycle cache) built for workflow runs that had **zero measured runs** | `wc -l`, `2026-11-22-induct-inline-as-default-measure-author/QUEST.md:265` |
| `skills/induct/workflows/*.js` is **2,245 LOC** (`induct-grade.js` alone is 1,022 LOC); `extensions/bp3-pi/` is **622 LOC**; ZERO other production `.js`/`.mjs`/`.ts` files exist in the repo (`test/pi-discovery.mjs` is the only remaining JS file) | `find` + `wc -l` (2026-11-23) |
| Literal dead code: `src/quest/cli.ml:40-47` (`let has = ... in ignore has;`), `src/quest/store.ml:115-118` (`if contains_sub ... then grade_required else grade_required`) | read directly (2026-11-23) |
| Duplicated primitives: `contains_sub` (`store.ml`, `config.ml`), `ensure_dir`/`mkdir_p` (`harness.ml`, `config.ml`, `worktree.ml`), 4 different Yojson string/member getters (`store.ml`, `hooks.ml`, `harness.ml`, `claude_tx.ml`), 2 atomic writers (`harness.ml`, `config.ml`), 4 hand-rolled flag parsers | `rg` audit (2026-11-23) |
| Naming drift: `worktree` appears 48 times in `worktree.ml` vs `desk` in docs; `e` variable names for nodes (old `exp`) across `main.ml`/`store.ml`; `bp3 g` header comment in `gitx.ml:1`; `names.ml` holds only 3 constants while 32+ `E_*` codes stay raw literals | `rg` audit (2026-11-23) |
| 4 overlapping induct skills (`induct` 290L, `induct-yolo` 152L, `induct-inline` 139L, `induct-inline-yolo` 71L) where `induct`/`induct-yolo` describe the dead Muse JS workflow engine | `wc -l skills/*/SKILL.md` |

Owner decision settled during framing (2026-11-23): aggressively retire Muse JS workflows (`2,245` LOC), `extensions/bp3-pi` (`622` LOC), and unused `harness.ml` supervisor/tape/watch/backtest/link code, keeping `bp3 harness desk` + preserving history via a git tag.

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
| existing OCaml engine, skills, tests, `Makefile`, `test/suites.tsv`, `CONSTRAINTS.md` | repo at post-`bp3-is-static` HEAD |
| owner `CONSTRAINTS.md` sign-off | required to remove `extensions/bp3-pi`, workflow scripts, and `@earendil-works/pi-coding-agent` (and `node` if `pi-discovery.mjs` retires) from `CONSTRAINTS.md` |

## Outputs

| Output | Shape |
|---|---|
| deleted dead surfaces | `skills/induct/workflows/`, `.agents/workflows/`, `extensions/bp3-pi/`, dead `harness.ml` subsystems, and their obsolete fixture suites removed cleanly |
| `src/quest/util.ml` | single home for string/fs/atomic-write/JSON helpers; zero duplicate copies across `src/quest/` |
| `src/quest/names.ml` | single home for every CLI verb/door/edge/state/flag/`E_*` code + test failing on rogue literals |
| consolidated skills | 2 sharp conducting skills (`induct` + `induct-yolo` running inline/`agy` mode, or `induct-inline` + `induct-inline-yolo` with dead workflow prose removed — settled in Open question 2) |
| faster `make check-full` | fewer obsolete fixture suites -> faster gate wall time |

## Acceptance gates

Observed today (2026-11-23):

```text
$ wc -l src/quest/harness.ml skills/induct/workflows/*.js extensions/bp3-pi/index.ts extensions/bp3-pi/src/*.ts | tail -n 1
    5679 total
$ rg -n "ignore has" src/quest/cli.ml
47:    ignore has;
$ rg -n "then grade_required else grade_required" src/quest/store.ml
118:      grade_required else grade_required in
$ wc -l src/quest/names.ml
       8 src/quest/names.ml
```

Design trace (after quest lands):

```text
retire.1  ls skills/induct/workflows extensions/bp3-pi -> No such file or directory
          CONSTRAINTS.md updated with owner sign-off row removing harness extensions / pi-coding-agent
          make check-full rc 0 (faster wall time, 0 retired suites left in test/suites.tsv)
retire.2  src/quest/harness.ml gone or <= 100 lines (thin desk delegation); bp3 harness desk prepare|check|exit|release|list still green
          bp3 harness supervisor -> E_USAGE (cleanly retired)
clean.1   src/quest/util.ml exists; zero duplicate contains_sub / ensure_dir / write_file_atomic; cli.ml:ignore has and store.ml:no-op gone
clean.2   src/quest/names.ml holds all doors, verbs, edges, states, flags, E_* codes; Store.reserved_slugs derived from Names;
          unit test fails if a new raw E_* code appears outside names.ml; gitx.ml:1 no longer says "bp3 g"
skills.1  zero dead Muse workflow prose left in skills/; all renders synced; test/skills.sh + test/mode.sh green
all       non-test LOC reduced by >= 4,500 lines; make check-full rc 0
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
| Deleting `skills/induct/workflows/*.js`, `.agents/workflows/`, `extensions/bp3-pi/`, and their tests (`retire.1`) | Merging `bin/bp3` into a single OCaml binary (`docs/icebox/2026-11-23-single-cli.md`, separate quest) |
| Deleting unused `harness.ml` subsystems (`supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, `link`) while keeping `harness desk` (`retire.2`) | Rewriting stored git ledger history (read-side `Layout.legacy_*` folds stay intact so old quests still read!) |
| `src/quest/util.ml`, removing dead code in `cli.ml`/`store.ml`, unifying duplicated helpers (`clean.1`) | Changing FSM semantics, `metrics.jsonl` schema, or `warden` rules |
| Promoting `2026-11-22-names-constants.md` (`names.ml`, `reserved_slugs`, `worktree` -> `desk` internal hygiene, `e` -> `node` var cleanup) (`clean.2`) | Deleting `test/pi-discovery.mjs` without explicit owner call (Open question 3) |
| Consolidating `induct*` skills as a dedicated skill node (`skills.1`) | |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **Removes** items from `CONSTRAINTS.md` (`@earendil-works/pi-coding-agent` library, `extensions/bp3-pi` + workflow scripts from the Surfaces table, and optionally `lang node` if `test/pi-discovery.mjs` retires). Per `CONSTRAINTS.md:77` ("Removing something works the same way"), requires an explicit **owner-words row** in the Sign-off log at approval!
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

| Row | Baseline (2026-11-23) | Target | Read from |
|---|---|---|---|
| non-test LOC | 14,073 | **< 9,500** (>= 4,500 cut) | `wc -l` |
| `src/quest/harness.ml` | 2,812 LOC | **deleted / <= 100 LOC** (desk only) | `wc -l` |
| `make check-full` wall time | ~37s (28 suites) | **measurably faster** (dead suites removed) | `run-suites` summary |
| `src/quest/names.ml` coverage | 3 constants | **100%** of CLI verbs/doors/edges/states/flags/`E_*` | `test_names.ml` literal guard |

## Risks and red chair

- **Strongest attack (breaking hidden callers of `harness.ml` or `bp3 n`/`bp3 e`):** "Deleting `link` and `harness.ml` breaks `bp3 n` / `bp3 e` (claimed context doors) and `Claude_tx.seconds` (which calls `Harness.epoch_of_iso` at `src/quest/claude_tx.ml:27`!)."
  - **Great catch — settled in design:**
    1. `epoch_of_iso` moves cleanly to `Tx` (in Quest 1) or `Util` (in `retire.2`/`clean.1`) BEFORE `harness.ml` is deleted — zero broken callers.
    2. `bp3 n` and `bp3 e` exist solely for `link claim` workflow children; Open question 1 explicitly asks the owner to confirm retiring `bp3 n`/`bp3 e` alongside `link` (if kept, a tiny 80-line `Link` module stays instead).
- **Second attack (breaking historical quest reads):** "Aggressive cleanup might accidentally delete `Layout.legacy_*` or `Store.fold_edge` and break `bp3 q r` on pre-rename quests."
  - **Settled in design:** Scope explicitly keeps all read-side `Layout.legacy_*` and `Store.fold_edge`/`fold_state_name` mappings untouched, and `test/unit/test_store.ml` (which pins `exp-era`, `graph-era`, and `quest-era` ledger samples) stays green throughout.
- **Attack on source (`ICEBOX.md` + owner prompt):**
  - *Overlap with `bp3-is-static`:* running `codebase-diet` before `2026-11-22-bp3-is-static-across-downstream-repo-worktrees` would cause merge conflicts in `bin/bp3`, `Makefile`, and `scripts/`. **Settled:** explicitly sequenced after `bp3-is-static` (and `fast-agy-induct` + `warden-v0`).
  - *Removing `node` from `CONSTRAINTS.md`:* `test/pi-discovery.mjs` is the only JS file left once `bp3-pi` and workflows go. Tracked as Open question 3 so we don't drop `node` silently without checking if the owner still runs `pi-discovery.mjs`.

## Open questions

1. Confirm retiring `bp3 n` / `bp3 e` (claimed context doors) alongside `harness link`, since `induct-inline` and `agy` `/swarm` always address `bp3 q <quest> n <node> e <edge>` directly? — **owner** (recommended: retire both).
2. In `skills.1`, collapse `induct` + `induct-inline` into a single `induct` (and `induct-yolo`) skill, OR delete `induct`/`induct-yolo` and keep `induct-inline`/`induct-inline-yolo`? — **owner** (recommended: collapse into `induct` + `induct-yolo` so the short name IS the default!).
3. Keep `test/pi-discovery.mjs` (keeping `node` in `CONSTRAINTS.md`) or retire it too so `bp3` becomes pure OCaml + Bash? — **owner**.
4. Fold in any architecture/abstraction takeaways from `docs/learn/get-good-harness-engineering.md` (Grok report) once written — **owner + agent**.

## Node diagram

```text
(after 2026-11-22-bp3-is-static lands)

retire.1 (drop Muse JS + bp3-pi) ──► retire.2 (slim harness.ml to desk) ──┬──► clean.1 (util.ml + dead code) ──► clean.2 (names.ml + desk hygiene)
                                                                          └──► skills.1 (consolidate induct* skills)
```
