---
status: proposed
home_repo: bp3
date: 2026-11-27
bump: minor
---

# single-cli: one OCaml `bp3` executable, zero `bp3-q`, thin self-mode dev stub

TL;DR
Port `init` and `skills install|check|prune-local` from the 666-line bash wrapper (`bin/bp3`) into a pure-OCaml + I/O library (`src/skills/`, `bp3_skills`), wire every verb (including `--version`, `-h`, `init`, `skills`, and retired `g`) into `src/quest/main.ml`, shrink repo `./bin/bp3` to a ~25-line self-mode exec stub (with fail-open hook guard), and install one single compiled `$PREFIX/bin/bp3` binary via `scripts/install-bp3.sh` — retiring `$PREFIX/bin/bp3-q` and `scripts/bp3-shim` permanently.

ELI5
Right now `bp3` is secretly two programs taped together: a 666-line bash script (`bp3`) that manages skills and hooks using `awk` and `jq`, and a compiled OCaml binary (`bp3-q`) that does everything else. That split breaks `bp3 --version`, forks bash + git on every single tool hook, duplicates CLI dispatch and repo-mode logic in two languages, and can pair the wrong `bp3-q` off `PATH`. This quest moves the skill/hook installer into OCaml (`src/skills/`) so `$PREFIX/bin/bp3` is one compiled executable with zero `bp3-q`, while keeping a tiny ~25-line `./bin/bp3` dev stub in this repo so hooks still fail open before `dune build`.

## Context

Promoted from `docs/icebox/2026-11-23-single-cli.md` (verbatim copy preserved at [ICEBOX.md](ICEBOX.md); original deleted from `docs/icebox/` per promotion rule).

Owner direction (2026-11-23 & 2026-11-27):
- "pls do not do bp3-q, its bp3"; "One binary" (merge wrapper into OCaml); "damn why did we have the bash wrapper" (2026-11-23).
- "yep i want one single cli before more refactors" (2026-11-27, after red-chairing `2026-11-23-single-cli.md`).

Measured ground (audited 2026-11-27 on `master` `4b68dc65`, `v0.13.0`):

| Fact | Source |
|---|---|
| `bin/bp3` grew from 373 lines (Nov 23) to **666 lines** (Nov 27), owning `CORE_SKILLS`, `DEV_SKILLS`, `RETIRED_WORKFLOWS`, `RETIRED_SKILLS`, `skills_install`, `skills_check`, `skills_prune_local`, `plan_claude_hooks_merge`, `plan_agy_hooks_merge`, completions install, and `repo add` | `bin/bp3:1-666` |
| `bp3 --version` fails with exit `2` (prints usage) because `bin/bp3:633-666` never forwards `--version` to `main.ml:929` | `bin/bp3:633-666`, `src/quest/main.ml:929` |
| Installed `bin/bp3` looks up `bp3-q` via `command -v bp3-q` on `PATH` instead of beside itself | `bin/bp3:375,617` |
| Self-mode detection derives `self` vs `host` from `git ls-files --error-unmatch -- src/quest bin/bp3`, so repo `./bin/bp3` must stay tracked as a thin dev stub (also failing open on `q hooks` when `_build/` is absent) | `src/quest/gitx.ml:212`, `src/quest/hooks.ml:674,684` |
| `scripts/check-skills` (25 lines, bash + `yq` v4 + `jq`) validates real YAML frontmatter (nested mappings, block scalars) and is tested directly by `test/skills.sh:56-78` | `scripts/check-skills`, `test/skills.sh:56-78` |
| `Gitx.root` defaults to `Sys.getcwd ()` when `BP3_ROOT` is unset, relying on `bin/bp3:622` (`BP3_ROOT="$(target_root)"`) in host mode | `src/quest/gitx.ml:23-26`, `bin/bp3:622` |
| `test/mode.sh:22-23` greps `CORE_SKILLS=`/`DEV_SKILLS=` from `bin/bp3`, and `scripts/check-retired-terms.sh:67` allowlists `bin/bp3:` for retired skill/workflow names | `test/mode.sh:22-23`, `scripts/check-retired-terms.sh:67` |
| Zero references to `bp3-q` exist in `skills/`, `AGENTS.md`, `CLAUDE.md`, `README.md`, or `RELEASING.md` — no skill edits required | `git grep bp3-q -- skills/ AGENTS.md CLAUDE.md README.md RELEASING.md` |

## Terms

| Term | Meaning |
|---|---|
| `bp3_skills` | new OCaml library under `src/skills/` (`skills.ml` pure core + `skills_io.ml` filesystem/git/process I/O), linked into `src/quest/main.exe` |
| `BP3_SELF_ROOT` | env var set by the thin repo `./bin/bp3` dev stub pointing to the repo root so OCaml locates `skills/`, `scripts/check-skills`, and `completions/` in self mode without `PATH` lookup |
| `share_dir` | resource directory (`skills/`, `scripts/check-skills`, `completions/`, `RELEASE`) resolved deterministically from `BP3_SHARE_DIR` -> `BP3_SELF_ROOT` -> `<dirname(realpath(Sys.executable_name))>/../share/bp3` |
| `self stub` | the ~25-line tracked `./bin/bp3` bash exec shim in the `bp3` repo that execs `${BP3_Q_BIN:-$root/_build/default/src/quest/main.exe}` and fails open on `q hooks` / `g hooks` when `_build/` is absent |
| `bp3-q` | retired binary name previously installed alongside the bash wrapper under `$PREFIX/bin/bp3-q`; removed by `scripts/install-bp3.sh` |
| `dist/bp3-v<ver>-<os>-<arch>` | new release artifact filename in `Makefile` & `scripts/install-bp3.sh` (replacing `dist/bp3-q-v...`) |

## Inputs

| Input | Source & precedence |
|---|---|
| `bp3 --version` / `bp3 -h` / `bp3 --help` | Top-level flags handled directly in `Main.run` (single binary) |
| `bp3 init [--global] [--harness=pi\|claude\|codex\|muse\|agy\|all]` | Alias of `bp3 skills install` handled in `Main.run` -> `Skills_io.run_install` |
| `bp3 skills install [--global] [--harness=...]` | Installs user-global `CORE_SKILLS` + non-clobbering hooks, self-mode repo-local `DEV_SKILLS` + `.pi/settings.json`, completions, and `Repo_io.add` auto-registration |
| `bp3 skills check` | Verifies render freshness (notice + body + `RELEASE` tag) across global `CORE_SKILLS` (+ self-local `DEV_SKILLS`); emits JSON verdict (`0` fresh, `1` `E_RENDER_STALE`) |
| `bp3 skills prune-local` | Safely removes legacy repo-local generated skills, retired workflows, and bp3 hook entries without touching user skills/hooks; emits JSON summary |
| `BP3_ROOT`, `BP3_TARGET`, `BP3_SELF_ROOT` | Root precedence: `Gitx.root` uses `BP3_ROOT` -> git toplevel of `$PWD` -> `Sys.getcwd ()`; `Skills_io.target_root` uses `BP3_TARGET` -> git toplevel of `$PWD` (when not self repo) -> `BP3_SELF_ROOT` -> git toplevel / `$PWD` |
| `BP3_GLOBAL_HOME`, `BP3_SKILLS_DIR`, `BP3_CHECK_SKILLS`, `BP3_SHARE_DIR`, `BP3_COMPLETIONS_DIR`, `BP3_SKIP_COMPLETIONS` | Existing env overrides preserved 100% identically for isolated test suites and `install-bp3.sh` |
| `BP3_Q_BIN` | Preserved in the ~25-line `./bin/bp3` dev stub only, so 18 existing test suites continue passing without churn |

## Outputs

| Output | Shape |
|---|---|
| `$PREFIX/bin/bp3` | Single compiled OCaml binary (zero bash wrapper, zero `$PREFIX/bin/bp3-q`) |
| `$PREFIX/share/bp3/` | Unchanged resource bundle: `skills/`, `scripts/check-skills`, `scripts/agy-statusline`, `completions/`, `RELEASE` |
| `./bin/bp3` (repo self stub) | ~25-line bash exec shim (down from 666 lines) with fail-open `q hooks` / `g hooks` when `_build/` is missing |
| `bp3 --version` | `<bp3_version>\n` (exit `0`) |
| `bp3 skills install` / `check` / `prune-local` | Byte-identical rendered `SKILL.md` files (with `<!-- GENERATED ... -->` notice), non-clobbering JSON hook merges, identical JSON verdicts (`E_RENDER_STALE` exit `1`, `--mode` refusal exit `2`) |
| `scripts/install-bp3.sh` | Installs `$artifact` directly to `$PREFIX/bin/bp3`, deletes any stale `$PREFIX/bin/bp3-q`, prints `installed bp3 <ver> -> <prefix>/bin/bp3 (was: <old>)` |
| `scripts/bp3-shim` | Deleted |

## Acceptance gates

Observed today (2026-11-27, `master` `4b68dc65`, `v0.13.0`):

```text
$ bp3 --version
usage: bp3 init ...   # exit 2 (broken!)
$ wc -l bin/bp3
     666 bin/bp3
$ ls -la ~/.local/bin/bp3 ~/.local/bin/bp3-q
-rwxr-xr-x ... ~/.local/bin/bp3      # bash script!
-rwxr-xr-x ... ~/.local/bin/bp3-q    # OCaml binary
$ ls src/skills
ls: src/skills: No such file or directory
```

Design trace (after quest lands):

```text
skills.1   # Pure OCaml bp3_skills library + unit & QCheck2 parity tests
           dune test -> test_skills passes (render round-trip, hook merge idempotence, prune-local JSON surgery, skill-set coverage)

cli.1      # Main.run owns init, skills, --version, -h, g; ./bin/bp3 shrinks to ~25 lines
           ./bin/bp3 --version            -> 0.13.0 (exit 0)
           wc -l bin/bp3                  -> <= 35 lines
           make check-full                -> 25/25 suites green (including 800+ assertions in test/skills.sh & test/mode.sh)

install.1  # Single installed binary, zero bp3-q, bp3-shim deleted
           PREFIX=$TMP/p scripts/install-bp3.sh $art
           file $TMP/p/bin/bp3            -> compiled executable (not #!)
           test ! -e $TMP/p/bin/bp3-q     -> exit 0 (even if stale bp3-q existed before install)
           PATH=$TMP/p/bin:$PATH bp3 --version && bp3 init-repo && bp3 q c demo && bp3 skills check
           make check-full                -> 25/25 suites green
```

## Goal and why

Eliminate the accidental two-binary split (`bp3` bash wrapper + `bp3-q` OCaml engine) before further architectural refactors (`split-src-quest`, `sqlite-quest-store`). Consolidating into one OCaml binary:
1. Moves 666 lines of untyped bash/`awk`/`jq` JSON surgery into type-checked OCaml (`src/skills/`, unit + QCheck2 tested in `dune test`).
2. Removes a `bash` + `git rev-parse` fork from every single harness hook (`PreToolUse`/`PostToolUse`/`SessionStart`/`Stop`).
3. Eliminates wrapper/engine drift (`bp3 --version` broken, duplicated CLI dispatch/help/mode detection, `PATH`-based `bp3-q` mismatch).

## Success picture

- `$PREFIX/bin/bp3` is one compiled OCaml executable owning every verb (`init`, `skills`, `q`, `n`, `e`, `warden`, `release`, `db`, `repo`, `ticket`, `harness`, `worktree`, `config`, `init-repo`, `--version`, `-h`), with `$PREFIX/bin/bp3-q` removed and never referenced.
- Installed `bp3` resolves `share/bp3/` relative to its own executable path (`Sys.executable_name`), never via `PATH`.
- Tracked `./bin/bp3` in the `bp3` repo is a `<= 35`-line dev exec stub that preserves self-mode detection (`git ls-files src/quest bin/bp3`), honors `BP3_Q_BIN` for tests, and fails open on `q hooks` / `g hooks` when `_build/` is absent.
- `bp3 skills install|check|prune-local` produces byte-identical renders and non-clobbering JSON merges, passing all of `test/skills.sh`, `test/mode.sh`, `test/install.sh`, `test/release-sync.sh`, `test/agy-statusline.sh`, and `make check-full`.
- Zero new languages, OCaml libraries, or CLI surfaces (`CONSTRAINTS.md` unchanged).

## Scope

| In | Out |
|---|---|
| New `src/skills/` (`bp3_skills`: `skills.ml`, `skills_io.ml`, `dune`) + `test/unit/test_skills.ml` | Replacing `scripts/check-skills` (`yq` v4 YAML validation stays in `share/bp3/scripts/check-skills`; zero new OCaml YAML deps) |
| Wire `init`, `skills`, `g`, `--version`, unified `-h` into `src/quest/main.ml` + git-toplevel fallback in `Gitx.root` | Ripping `BP3_Q_BIN` out of 18 test files (preserved in the ~25-line dev stub to keep diff tight) |
| Shrink `./bin/bp3` from 666 lines to ~25-line self-mode dev stub | Deleting `./bin/bp3` (required by self-mode detection and cold-clone hook fail-open) |
| Update `scripts/install-bp3.sh`, `Makefile` (`dist/bp3-v...`), `test/install.sh`, `test/release-sync.sh`, `test/agy-statusline.sh`, `test/mode.sh`, `scripts/check-retired-terms.sh`; delete `scripts/bp3-shim` | Refactoring `src/quest/` into domain libraries (`docs/icebox/2026-11-24-split-src-quest.md` stays separate) |
| Zero skill edits (`git grep bp3-q -- skills/` = 0 matches) | Removing `lang bash` from `CONSTRAINTS.md` (still used by `scripts/` and `test/*.sh`) |

## Human touchpoints

- **Quest approval (before `induct`):** Owner reviews/settles `QUEST.md` (directly or via `/red-ink`) and kicks off `/induct` / `/induct-yolo`.
- **Promotion (`bp3 release`):** Owner runs `BP3_DECIDER=human ./bin/bp3 release 2026-11-27-single-cli` (`v0.14.0`) after `/warden`.

## Nodes

### Milestone: skills

### skills.1 - ocaml-skills-installer-lib
Create the `bp3_skills` OCaml library (`src/skills/{dune,skills.ml,skills_io.ml}`) implementing byte-identical skill rendering, freshness checking, non-clobbering Claude/Muse/agy hook JSON merges, `.pi/settings.json` exclusion updates, `prune-local` cleanup, completions delivery, and in-process `Repo_io.add` registration, with unit + QCheck2 tests in `test/unit/test_skills.ml`. — [NODE.md](nodes/node-skills-1-ocaml-skills-installer-lib/NODE.md)

### Milestone: cli

### cli.1 - wire-single-cli-and-thin-self-stub
Link `bp3_skills` into `src/quest/main.exe`, wire `init`, `skills install|check|prune-local`, `g`, `--version`, and unified `-h` into `src/quest/main.ml`, add git-toplevel fallback to `Gitx.root`, shrink `./bin/bp3` from 666 lines to a ~25-line dev exec stub (zero `PATH` lookup for `bp3-q`), update `test/mode.sh` + `scripts/check-retired-terms.sh`, and pass `make check-full`. — [NODE.md](nodes/node-cli-1-wire-single-cli-and-thin-self-stub/NODE.md)

### Milestone: install

### install.1 - retire-bp3-q-and-single-binary-install
Install the compiled OCaml binary directly to `$PREFIX/bin/bp3` in `scripts/install-bp3.sh` (removing stale `$PREFIX/bin/bp3-q`), rename the release artifact in `Makefile` to `dist/bp3-v<ver>-<os>-<arch>`, delete `scripts/bp3-shim`, and update `test/install.sh`, `test/release-sync.sh`, and `test/agy-statusline.sh` to verify single-binary host mode end-to-end. — [NODE.md](nodes/node-install-1-retire-bp3-q-and-single-binary-install/NODE.md)

## Scorecard

| Metric | Target |
|---|---|
| `bin/bp3` line count (self stub) | `<= 35` lines (down from `666`) |
| Installed binaries in `$PREFIX/bin` | `1` (`bp3` compiled OCaml; `0` `bp3-q`) |
| `bp3 --version` exit code | `0` (prints `<bp3_version>`) |
| Skill render & hook JSON parity (`test/skills.sh`, `test/mode.sh`) | `100%` green |
| `make check-full` | `25/25` suites green |

## Risks and red chair

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Pure OCaml (`stdlib`, `unix`, `str`, `yojson`, `ounit2`, `qcheck-core`) + existing `scripts/check-skills` (`yq`/`jq`). Zero new languages, OCaml libraries, or CLI surfaces.
- **Common-sense pass (`CONTEXT.md`):** Aligns with `Q1` ("exact work lives in deterministic scripts/tools", here compiled type-checked OCaml under `dune test`) and `bp3 lessons (2026-11-19)` (porting complex bash/perl scripts into OCaml eliminates quoting/JSON bugs and shell-fork overhead).
- **Red chair of the icebox source (`docs/icebox/2026-11-23-single-cli.md`, conducted 2026-11-27 — all Critical/Major concerns settled):**
  1. *Stale scope & size (Major — settled):* Icebox estimated 373 lines and waited on a now-canceled static quest; actual `bin/bp3` is 666 lines including global skills, non-clobbering hook merges, `prune-local`, and `skills check`. Settled by scoping `skills.1` explicitly around all 666 lines with pure JSON planners + QCheck2 idempotence laws.
  2. *Self-mode `./bin/bp3` cannot be deleted (Major — settled):* `Gitx.repo_mode` (`gitx.ml:212`) and `Hooks` (`hooks.ml:674,684`) derive self mode from tracked `src/quest` + `bin/bp3`, and cold clones need fail-open `q hooks`. Settled in `cli.1`: installed `$PREFIX/bin/bp3` is pure OCaml (zero wrapper); tracked `./bin/bp3` shrinks to a ~25-line dev exec stub with fail-open hooks.
  3. *Host-mode `Gitx.root` from subdirectories vs `test/config.sh:41` nogit fixture (Major — settled):* Without the bash wrapper running `BP3_ROOT="$(target_root)"`, compiled `$PREFIX/bin/bp3` invoked from a subdirectory needs git-toplevel discovery in `Gitx.root`, while `./bin/bp3` must still pass `BP3_ROOT="${BP3_ROOT:-$root}"` so `"$work/nogit/bin/bp3" config` roots at `$work/nogit`. Both paths are explicitly specified in `cli.1`.
  4. *`BP3_Q_BIN` 57-occurrence blast radius & `scripts/check-skills` YAML dep (Minor — settled):* Dev stub retains `BP3_Q_BIN` fallback so 18 unrelated test files stay untouched; `Skills_io` keeps calling `share/bp3/scripts/check-skills` so real `yq` YAML validation stays intact with zero new OCaml libraries.

## Open questions

None blocking `induct`.

## Node diagram

```text
Cohort 1:   [ skills.1 - ocaml-skills-installer-lib ]
                               |
                               v
Cohort 2:   [ cli.1 - wire-single-cli-and-thin-self-stub ]
                               |
                               v
Cohort 3:   [ install.1 - retire-bp3-q-and-single-binary-install ]
```
