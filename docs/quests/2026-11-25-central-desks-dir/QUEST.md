---
status: landed
home_repo: bp3
date: 2026-11-25
bump: minor
---

# central-desks-dir: move all desks and metadata to `~/.bp3/desks/`, kill nesting and `Makefile` `--root=.` hack

TL;DR
Move every quest desk, grade/run desk, and desk metadata file out of repo-nested `.bp3/` into one central machine-local root (`$BP3_DESKS_DIR` or `~/.bp3/desks/`) keyed by `<repo>-<hash8>` of the repo's canonical `git_common_dir`, placing quest desks (`quests/<quest>`) and run desks (`runs/<quest>/<node>/<run_id>`) as **siblings** so a grade desk can never nest inside a quest desk. Keep read+release fallback for pre-existing `.bp3/desks/*.json` and dual-prefix transcript discovery in `src/quest/metrics_io.ml` so historical quests never regress. Delete the `Makefile:7-8` `--root=.` dune workaround (and tighten `scripts/check-gates`), then unify `skills/induct/SKILL.md` so self and host repos both author in their central quest desk.

ELI5
Right now `bp3` hides git worktrees inside `.bp3/worktrees/` right inside your repo. That breaks tools like `dune` that walk up folders looking for a project root (which forced a gross `--root=.` hack in `Makefile`), AND it even nested grade desks *inside* quest desks so `git add -A` could accidentally stage a grade desk as a gitlink! Moving every desk and its `.meta/` JSON into `~/.bp3/desks/<repo>-<hash>/{quests,runs,.meta}` fixes dune everywhere, makes quest/grade nesting impossible, keeps every repo completely free of `.bp3/` furniture, and lets host repos like `~/m/predictor` use isolated desks identically to `bp3`.

## Context

Promotes `docs/icebox/2026-11-24-central-desks-dir.md` (copied verbatim to [ICEBOX.md](ICEBOX.md) and deleted from `docs/icebox/`). Unblocked now that `2026-11-23-codebase-diet` landed as `v0.5.0` (`c8bfbb9`), and directly motivated by the live grade-desk nesting collision observed during `codebase-diet` `skills.1` (`docs/quests/2026-11-23-codebase-diet/FEEDBACK.md`, Proposal #3).

Measured ground (audited 2026-11-25 on `master` `c8bfbb9`, `v0.5.0`):

| Fact | Source |
|---|---|
| `Layout.desks_root = ".bp3/worktrees"` and `Layout.desk_dir q = ".bp3/worktrees/" ^ q`; `Worktree.derive_path` returns `.bp3/worktrees/<q>/<n>/<r>` — directly nested inside the quest desk `.bp3/worktrees/<q>` | `src/quest/layout.ml:22,44`, `src/quest/worktree.ml:31-35` |
| `Worktree.desks_dir` (`worktree.ml:174`) and `Config.list_desks` (`config.ml:35`) both hardcode `Filename.concat root ".bp3/desks"`, breaking when invoked from inside a worktree (`root` is the desk, not the main checkout) | `src/quest/worktree.ml:174`, `src/quest/config.ml:34-49` |
| `Makefile:7-8` carries `$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)` to hide nested-worktree dune root breakage; `scripts/check-gates:51-52` allows `( --root=\.)?` solely for that hack | `Makefile:7-8`, `scripts/check-gates:11,51-52` |
| `Metrics_io.default_dirs` and `default_pi_dirs` match only `main_root` and `main_root ^ "/" ^ Layout.desks_root` | `src/quest/metrics_io.ml:56-90` |
| `Warden_io.open_desks_for` already delegates to `Worktree.load_records ()` (only its comment mentions `.bp3/desks`) | `src/warden/warden_io.ml:65-73` |
| `skills/induct/SKILL.md:21-23` still says `"In self mode, prepare the quest desk ... and author only there; host mode works in the repo"` | `skills/induct/SKILL.md:21-23` |
| Owner direction (2026-11-24): `"yeah, idc about agent sandboxes, let's go for ~/.bp3/desks, let's ignore agent sandboxes"` | `ICEBOX.md`, session 2026-11-24 |

## Terms

| Term | Meaning |
|---|---|
| `BP3_DESKS_DIR` | optional env var overriding the central desks base directory (used by tests for isolation and by custom setups); defaults to `$HOME/.bp3/desks` |
| `desks_base` | resolved central root directory: `$BP3_DESKS_DIR` when non-empty, else `$HOME/.bp3/desks` |
| `repo_key` | deterministic per-repo folder name `<repo_slug>-<hash8>` derived from canonical `git_common_dir`: sanitized basename of repo root (lowercase `[a-z0-9-]`, fallback `"repo"`) + first 8 hex chars of `Digest.to_hex (Digest.string canon_common_dir)` |
| `repo_desks_dir` | `<desks_base>/<repo_key>` — the single machine-local bucket holding all desks and metadata for one git repository |
| `quest_desk_dir` | `<repo_desks_dir>/quests/<quest>` — the quest-level authoring worktree (`bp3 harness desk prepare --quest <quest>`) |
| `run_desk_dir` | `<repo_desks_dir>/runs/<quest>/<node>/<run_id>` — a node or detached grade worktree (`bp3 harness desk prepare <quest> <node> --run <run_id>`), sibling to `quests/`, never nested inside it |
| `desks_meta_dir` | `<repo_desks_dir>/.meta` — one `<run_id>.json` file per open desk, published exclusively via `Unix.link` |
| `legacy_desks_root` | `.bp3/worktrees` — read-only legacy path prefix kept solely so `metrics_io.ml` still discovers historical transcripts |
| `legacy_desks_meta_dir` | `.bp3/desks` — read-only fallback directory checked by `Worktree.load_record`/`load_records` and cleaned by `delete_record` during upgrade transition; never written to |

## Inputs

| Input | Source & precedence |
|---|---|
| `BP3_DESKS_DIR` | process env; wins over `$HOME/.bp3/desks` when set and non-empty |
| `HOME` | process env; fallback base `$HOME/.bp3/desks` when `BP3_DESKS_DIR` is unset/empty |
| `--path <dir>` | CLI flag on `bp3 harness desk prepare <q> <n> --run <id> --path <dir>`; wins over derived `run_desk_dir` for that run |
| `git rev-parse --git-common-dir` | resolved via `Gitx.git_common_dir ()` and `Unix.realpath`; anchors `repo_key` identically from the main checkout or from any linked worktree (falls back to canonical `root` only outside git) |
| legacy `.bp3/desks/*.json` | read-only transition input under `<main_root>/.bp3/desks/`; shadowed by central `.meta/<run_id>.json` if the same `run_id` exists in both |

## Outputs

| Output | Shape |
|---|---|
| `bp3 harness desk derive <q> <n> <r>` | `{"ok":true,"path":"<desks_base>/<repo_key>/runs/<q>/<n>/<r>"}` (absolute path, never inside the repo or inside `quests/<q>`) |
| `bp3 harness desk prepare --quest <q>` | creates worktree on `quest/<q>` at `<desks_base>/<repo_key>/quests/<q>` and writes `<desks_base>/<repo_key>/.meta/quest-<q>.json`; creates zero files under `<repo>/.bp3/` |
| `bp3 harness desk prepare <q> <n> --run <r> [--commit <sha>]` | creates worktree at `<desks_base>/<repo_key>/runs/<q>/<n>/<r>` (or `--path`) and writes `<desks_base>/<repo_key>/.meta/<r>.json` |
| `bp3 harness desk list` / `exit` / `release` / `check` | identical JSON schema; resolves `<repo_key>` from `git_common_dir` so commands work identically from main checkout or inside any desk; reads & releases legacy `.bp3/desks/*.json` transparently |
| `bp3 config` | identical JSON schema (`desks` array populated via `Worktree.load_records ()`), consistent from both main checkout and any worktree, strictly read-only |
| `bp3 q <q> metrics scrape` | scans Claude (`~/.claude/projects/`) and pi (`~/.pi/agent/sessions/`) dirs matching `main_root`, `<desks_base>/<repo_key>/...`, AND legacy `<main_root>/.bp3/worktrees/...` |
| `Makefile` & `scripts/check-gates` | `DUNE_BUILD` and `DUNE_TEST` drop `$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)`; `scripts/check-gates` rejects `--root=.` |
| `skills/induct/SKILL.md` (+ renders) | unified self + host desk workflow (`bp3 harness desk prepare --quest <quest>` for every repo, no `"host mode works in the repo"` branch) |

## Acceptance gates

Observed today (2026-11-25, `master` `c8bfbb9`, `v0.5.0`):

```text
$ ./bin/bp3 harness desk derive demo node-a R1
{"ok":true,"path":".bp3/worktrees/demo/node-a/R1"}
$ grep -n -- "--root=" Makefile scripts/check-gates
Makefile:7:DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
Makefile:8:DUNE_TEST = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
scripts/check-gates:11:#   dune build of both binaries (SDKROOT= and --root=. allowed)
scripts/check-gates:51:  "$dune build( --root=\\.)? src/quest/main\\.exe src/quest/run_suites\\.exe"
scripts/check-gates:52:  "$dune test( --root=\\.)?"
$ grep -n "host mode works in the repo" skills/induct/SKILL.md
23:   and author only there; host mode works in the repo. One session
```

Design trace (after quest lands):

```text
desks.1   BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare --quest q1
            -> {"ok":true,"path":"/tmp/d/bp3-<8hex>/quests/q1","ref":"quest/q1",...}
          BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare q1 node-1 --run grade-n1-c1-a1 --commit HEAD
            -> {"ok":true,"path":"/tmp/d/bp3-<8hex>/runs/q1/node-1/grade-n1-c1-a1",...}
          # sibling dirs: quest desk git status stays clean while grade desk is open; <repo>/.bp3/ is never created
          # calling bp3 harness desk list / bp3 config from inside either desk returns the exact same desks
          # pre-existing <repo>/.bp3/desks/OLD.json shows in desk list and deletes cleanly on desk release --run OLD
          dune test (test_layout.ml) && ./test/worktree.sh && ./test/config.sh && make check-full -> rc 0
desks.2   metrics_io default_dirs & default_pi_dirs match main_root, $BP3_DESKS_DIR/<repo_key>/..., AND legacy <main_root>/.bp3/worktrees/...
          ./test/metrics.sh && make check-full -> rc 0
cleanup.1 grep -n -- "--root=" Makefile scripts/check-gates -> 0 matches
          dune build & dune test inside a central desk run cleanly with zero --root=. flag
          ./scripts/check-gates && ./test/check-tiers.sh && make check-full -> rc 0
skills.1  grep -n "host mode works in the repo" skills/ .agents/skills/ .claude/skills/ .pi/skills/ -> 0 matches
          ./bin/bp3 skills check -> {"ok":true,...}
          ./test/skills.sh && ./test/mode.sh && make check-full -> rc 0
all       25/25 suites green; zero files created in <repo>/.bp3/ by any desk command;
          Makefile --root=. hack gone; self and host repos share one central ~/.bp3/desks/ engine
```

## Goal and why

Eliminate nested repo worktrees permanently. Nesting desks inside `.bp3/worktrees/` broke `dune` root discovery (forcing a repo-specific `Makefile` `--root=.` hack while leaving downstream repos like `~/m/predictor` broken), nested grade desks inside quest desks (causing live gitlink `160000` collisions during concurrent authoring), and forced `skills/induct/SKILL.md` to disable desks in host mode. One central `~/.bp3/desks/<repo>-<hash>/{quests,runs,.meta}` layout solves all three root causes at once with zero mode branching.

## Success picture

- `bp3 harness desk prepare` puts every quest desk under `<desks_base>/<repo_key>/quests/<quest>`, every run/grade desk under `<desks_base>/<repo_key>/runs/<quest>/<node>/<run_id>`, and metadata under `<desks_base>/<repo_key>/.meta/<run_id>.json` — creating zero files inside `<repo>/.bp3/`.
- Quest desks and grade desks are siblings and can never nest inside each other.
- `Makefile` contains zero `--root=.` workaround, `scripts/check-gates` enforces its absence, and `make check` runs cleanly from inside a central desk.
- `bp3 q <q> metrics scrape` discovers Claude and pi transcripts from both central desks and legacy `.bp3/worktrees/` desks, and `bp3 harness desk list`/`release` handles pre-existing `.bp3/desks/*.json` smoothly.
- `skills/induct/SKILL.md` (and all harness renders) uses the same central quest desk flow for both self and host repos.

## Scope

| In | Out |
|---|---|
| Central desk root `$BP3_DESKS_DIR` / `~/.bp3/desks/<repo>-<hash8>/` with sibling `quests/`, `runs/`, and `.meta/` (`desks.1`) | Agent sandbox plumbing (e.g. `.claude/settings.json` `additionalDirectories` — explicitly ignored per owner 2026-11-24) |
| Resolving `repo_key` from canonical `git_common_dir ()` across `worktree.ml`, `config.ml`, `warden_io.ml` (`desks.1`) | Storing desks in `bp3.sqlite` or mixing build worktrees into `~/.local/share/bp3/` (keep `Unix.link` lock-free `.meta/*.json` files) |
| Read+release fallback for pre-existing `<main_root>/.bp3/desks/*.json` (`desks.1`) and dual-prefix transcript discovery in `metrics_io.ml` (`desks.2`) | Removing `.bp3/` from this repo's `.gitignore` (1-line safety net for any leftover legacy local desks on developer machines) |
| Deleting `Makefile:7-8` `--root=.` hack and tightening `scripts/check-gates` + `test/check-tiers.sh` (`cleanup.1`) | Editing downstream repos like `~/m/predictor` (optional post-release dogfood check) |
| Updating `skills/induct/SKILL.md` + re-rendering `.{agents,claude,pi}/skills/` + `test/skills.sh` (`skills.1`) | Merging `bin/bp3` into OCaml (`single-cli`) or splitting `src/quest/` (`split-src-quest`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Adds zero languages, zero libraries (uses OCaml stdlib `Digest`, `Unix`, `Filename`), and zero new CLI surfaces (`bp3 harness desk`, `bp3 config`, `bp3 warden`, `bp3 q metrics` are all already signed). No edit to `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Q3 Scaling (`CONTEXT.md:39`, checked 2026-11-19): *"A git worktree per agent or task is the mainstream isolation (Claude Code sub-agents, worktrunk, Gas Town). bp3: desks."* Placing worktrees outside the repo tree avoids upward root-walker breakage (`dune`, `opam`, pre-commit hooks) without cluttering `~/m/` with sibling `<repo>.desks/` directories.
  - Q6 Chesterton's fence (`CONTEXT.md:82`, checked 2026-11-19): `.bp3/worktrees/` existed to stay repo-relative and gitignored without a central path convention; `Makefile:7-8` patched around dune's root walk only for `bp3` itself. Moving to `~/.bp3/desks/<repo>-<hash8>/` eliminates the root cause so the fence comes down cleanly.
  - Q6 DRY (`CONTEXT.md:87`, checked 2026-11-19): sharing `Worktree.load_records ()` across `worktree.ml`, `config.ml`, and `warden_io.ml` eliminates `config.ml:35`'s divergent `root/.bp3/desks` reader.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (optional `/red-ink` if any design detail changes) | owner |
| Promote & release (`goal_fin`: `/warden` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-central-desks-dir`) | owner |

## Nodes

### Milestone: desks

| Node | TL;DR |
|---|---|
| [desks.1 - central-layout-and-worktree](nodes/node-desks-1-central-layout-and-worktree/NODE.md) | central `~/.bp3/desks/<repo>-<hash8>/{quests,runs,.meta}` (`BP3_DESKS_DIR` override), `git_common_dir` bucketing, legacy `.bp3/desks/` read+release fallback, unified `config.ml`/`worktree.ml`, `test_layout.ml` + `worktree.sh` + `config.sh` |
| [desks.2 - metrics-dual-slug](nodes/node-desks-2-metrics-dual-slug/NODE.md) | update `metrics_io.ml` (`default_dirs` + `default_pi_dirs`) to discover Claude/pi transcripts from both central `$BP3_DESKS_DIR/<repo_key>/` and legacy `<main_root>/.bp3/worktrees/` + `test/metrics.sh` |

### Milestone: cleanup

| Node | TL;DR |
|---|---|
| [cleanup.1 - drop-makefile-root-hack](nodes/node-cleanup-1-drop-makefile-root-hack/NODE.md) | delete `Makefile:7-8` `--root=.` workaround, tighten `scripts/check-gates` to reject `--root=.`, update `test/check-tiers.sh`, prove `make check` runs clean from a central desk |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - unify-host-and-self-desk-prose](nodes/node-skills-1-unify-host-and-self-desk-prose/NODE.md) | drop `"host mode works in the repo"` split from `skills/induct/SKILL.md`, re-render `.{agents,claude,pi}/skills/`, and lock with `test/skills.sh` |

## Scorecard

| Row | Baseline (2026-11-25, `c8bfbb9`) | Target | Read from |
|---|---|---|---|
| default desk path | `.bp3/worktrees/<q>/<n>/<r>` (nested in repo & in quest desk) | `$BP3_DESKS_DIR` or `~/.bp3/desks/<repo>-<hash8>/{quests,runs}/...` | `bp3 harness desk derive` |
| files written inside `<repo>/.bp3/` by new desks | `.bp3/worktrees/*` + `.bp3/desks/*.json` | **0 files** | `test/worktree.sh`, `test/config.sh` |
| `Makefile` `--root=.` hack lines | 2 lines (`Makefile:7-8`) + 3 allowlist lines (`scripts/check-gates`) | **0 lines** | `grep -c -- "--root=" Makefile scripts/check-gates` |
| `metrics_io` desk roots scanned | legacy `.bp3/worktrees/` only | central `<desks_base>/<repo_key>/` **+** legacy `.bp3/worktrees/` | `test/metrics.sh` |
| self vs host desk branching in `skills/induct/SKILL.md` | 1 split (`"host mode works in the repo"`) | **0** (unified central desk flow) | `test/skills.sh` |

## Risks and red chair

Red chair of the plan AND the icebox source (`ICEBOX.md`, Step 7.5):

- **Attack 1 (Critical — icebox source missed quest-vs-grade desk nesting):**
  - `ICEBOX.md` sketched `~/.bp3/desks/<repo>-<hash>/<run_id>` without addressing that `prepare --quest <q>` (`<root>/<q>`) and `prepare <q> <n> --run <r>` (`<root>/<q>/<n>/<r>`) previously nested inside each other — causing a live gitlink `160000` + dirty-worktree failure during `codebase-diet` `skills.1`.
  - **Settled in `desks.1`:** Separate sibling subtrees `<repo_desks_dir>/quests/<quest>` and `<repo_desks_dir>/runs/<quest>/<node>/<run_id>`, proved by a QCheck2 non-nesting invariant in `test/unit/test_layout.ml` and a concurrent quest+grade desk check in `test/worktree.sh`.
- **Attack 2 (Major — invoking `bp3 harness desk list/exit` or `bp3 config` from inside a central desk):**
  - Today `worktree.ml:174` and `config.ml:35` compute `Filename.concat root ".bp3/desks"`. Inside a central desk, `root` is the desk path, NOT the main checkout, so hashing `root` would point at a different bucket.
  - **Settled in `desks.1`:** Always derive `repo_key` from canonical `git_common_dir ()` (shared by main repo and every worktree), and route `config.ml:list_desks` through `Worktree.load_records ()`. Proved by running `bp3 harness desk list`, `bp3 harness desk exit`, and `bp3 config` from inside a central desk in `test/worktree.sh` and `test/config.sh`.
- **Attack 3 (Major — standalone test scripts polluting real `~/.bp3/desks/`):**
  - Moving default desks outside `$work/repo` means running `./test/worktree.sh` or `./test/config.sh` directly would touch real `~/.bp3/desks/` unless isolated.
  - **Settled in `desks.1` + `desks.2`:** `BP3_DESKS_DIR` overrides `$HOME/.bp3/desks`; every desk/config/metrics test exports `BP3_DESKS_DIR="$work/desks"` (and `run-suites` already isolates `HOME`).
- **Attack 4 (Major — breaking existing open `.bp3/desks/` desks or historical `metrics scrape` on upgrade):**
  - **Settled in `desks.1` + `desks.2`:** `worktree.ml` falls back read-only to `<main_root>/.bp3/desks/*.json` and unlinks legacy records on `release` (never writing new files there); `metrics_io.ml` matches both central `<desks_base>/<repo_key>/` and legacy `<main_root>/.bp3/worktrees/` transcript slugs.
- **Attack 5 (Minor — symlinked `/tmp` -> `/private/tmp` on macOS breaking `orphan_entry` or `metrics_io` slug matching):**
  - **Settled in `desks.1` + `desks.2`:** Canonicalize both sides with `Unix.realpath` (when existing) in `orphan_entry` and include both logical and realpath variants in `metrics_io.ml` (matching its existing `main_root` pattern).

## Open questions

| # | Question | Owner | Default if untouched |
|---|---|---|---|
| 1 | Downstream `~/m/predictor` `_opam` / `.githooks/pre-commit` behavior when running from `~/.bp3/desks/predictor-<hash>/quests/<q>` | owner (post-release dogfood) | Out of scope for `bp3` itself; verify on first `predictor` quest after `v0.6.0` lands |

## Node diagram

```text
Wave 1: desks.1 (central-layout-and-worktree: ~/.bp3/desks/<repo>-<hash8>/{quests,runs,.meta},
                 BP3_DESKS_DIR, git_common_dir bucketing, legacy .bp3/desks fallback,
                 config.ml unified reader, test_layout.ml + worktree.sh + config.sh)
           │
           ├──────────────────────────────────┬────────────────────────────────────┐
Wave 2: desks.2 (metrics-dual-slug)      cleanup.1 (drop-makefile-root-hack)   skills.1 (unify-host-and-self-desk-prose)
        metrics_io.ml + test/metrics.sh  Makefile + check-gates + tiers.sh     skills/induct/SKILL.md + renders + skills.sh
```
