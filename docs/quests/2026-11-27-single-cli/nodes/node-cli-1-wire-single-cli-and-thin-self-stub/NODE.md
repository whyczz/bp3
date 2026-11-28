---
node: cli.1
slug: wire-single-cli-and-thin-self-stub
kind: code
lane: standard
status: proposed
depends_on:
  - skills.1 - ocaml-skills-installer-lib
---

# cli.1 - wire-single-cli-and-thin-self-stub

TL;DR
Link `bp3_skills` into `src/quest/main.exe`, wire `init`, `skills install|check|prune-local`, `g` (retired door), `--version`, and unified `-h`/`--help` into `src/quest/main.ml`, add git-toplevel fallback to `Gitx.root`, shrink tracked `./bin/bp3` from 666 lines to a `<= 35`-line self-mode dev exec stub (zero `PATH` lookup for `bp3-q`), and update `test/mode.sh` + `scripts/check-retired-terms.sh`.

## Acceptance gates

Design trace:

```text
# 1. bp3 --version works directly (fixed from exit 2)
$ ./bin/bp3 --version
0.13.0

# 2. ./bin/bp3 is a thin dev stub (<= 35 lines, zero bp3-q PATH lookup)
$ wc -l bin/bp3
      24 bin/bp3
$ grep -c "bp3-q" bin/bp3
0

# 3. Direct OCaml binary handles init and skills without any bash wrapper
$ _build/default/src/quest/main.exe skills check
{"ok":true,"fresh":[],"skills_checked":...}

# 4. Hooks still fail open when _build/ is absent
$ echo '{}' | BP3_Q_BIN=/nonexistent ./bin/bp3 q hooks
# exits 0 with warning on stderr

# 5. Full suite (800+ skill assertions, mode, hooks, completion, config, g) passes
$ make check-full
run-suites: ok 25/25
```

Runnable goal block:
- **objective:** Make `src/quest/main.exe` the single authoritative CLI for every `bp3` verb and reduce `./bin/bp3` to a tiny self-mode dev stub.
- **prove by:** `./bin/bp3 --version`, `wc -l bin/bp3`, direct `main.exe skills ...` calls, cold fail-open hook check, and `make check-full`.
- **done when:** `make check-full` passes 25/25 suites, `bin/bp3` is `<= 35` lines with zero `bp3-q` references, and `main.exe` owns `init`, `skills`, `g`, `--version`, and `-h`.

## Diagram

```text
Installed host mode ($PREFIX/bin/bp3, wired in install.1):
  $PREFIX/bin/bp3 <args> --------------------------------------+
                                                               v
Self dev mode (./bin/bp3, ~25-line stub):               src/quest/main.ml
  |-- _build/.../main.exe (or $BP3_Q_BIN) exists ------>  |-- --version  -> bp3_version (exit 0)
  |     (sets BP3_SELF_ROOT=$root, BP3_ROOT=${BP3_ROOT:-$root})
  |                                                       |-- -h|--help  -> unified usage_text
  |-- missing + (q|g hooks) -> drain stdin, exit 0        |-- init       -> Skills_io.run_install
  +-- missing + other       -> error msg, exit 2          |-- skills ... -> Skills_io.run_{install,check,prune_local}
                                                          |-- g ...      -> retired door (g hooks fail-open exit 0, else exit 2)
                                                          +-- q|warden|release|db|repo|ticket|harness|worktree|config|init-repo
```

## Pseudocode

```python
# bin/bp3 (self-mode dev stub, ~25 lines)
#   root = dirname(dirname(BASH_SOURCE[0]))
#   gb = env.get("BP3_Q_BIN") or f"{root}/_build/default/src/quest/main.exe"
#   if executable(gb):
#       # Preserve caller-set BP3_ROOT; default to $root so fixtures like $work/nogit/bin/bp3 config
#       # root at $work/nogit, while db/repo/ticket ignore BP3_ROOT.
#       exec(gb, argv, env={"BP3_SELF_ROOT": root, "BP3_ROOT": env.get("BP3_ROOT", root)})
#   if argv[:2] in (["q", "hooks"], ["g", "hooks"]):
#       drain_stdin()
#       print_stderr("bp3 q hooks: no binary built; dune build src/quest/main.exe")
#       exit(0)
#   print_stderr("build bp3 first: dune build src/quest/main.exe")
#   exit(2)

# src/quest/gitx.ml:root (when invoked directly without dev stub, e.g. installed $PREFIX/bin/bp3)
def default_root() -> str:
    if env.get("BP3_ROOT"):
        return env["BP3_ROOT"]
    top = git_rev_parse_show_toplevel(cwd())
    return top if top else cwd()
```

## Fields

| Field | Value |
|---|---|
| Intent | Wire `bp3_skills` and unified CLI dispatch into `main.ml`, add git-toplevel root fallback in `gitx.ml`, and shrink `bin/bp3` to a ~25-line dev stub |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/quest/{dune,gitx.ml,main.ml}`, thin `bin/bp3`, updated `test/mode.sh`, `test/hooks.sh`, `scripts/check-retired-terms.sh`, `test/unit/test_main.ml` |
| Acceptance | Fails today (`./bin/bp3 --version` exits 2, `bin/bp3` is 666 lines, `main.exe skills check` fails); passes when `make check-full` is 25/25 green and `bin/bp3` is `<= 35` lines |
| Depends on | `skills.1 - ocaml-skills-installer-lib` |

## Prose & edge cases

- **Root resolution parity (`test/config.sh:41` vs host subdirectories):**
  - When the compiled binary runs **directly** (installed `$PREFIX/bin/bp3` with `BP3_ROOT` unset), `Gitx.root` resolves `git -C <cwd> rev-parse --show-toplevel` (falling back to `Sys.getcwd ()` outside git), so running `bp3 q r foo` from `~/m/predictor/src` finds `~/m/predictor` automatically without a bash wrapper!
  - When the dev stub `./bin/bp3` runs, it exports `BP3_SELF_ROOT="$root"` and `BP3_ROOT="${BP3_ROOT:-$root}"` (unless `door` is `db|repo|ticket` or `skills|init`, where `Skills_io` uses `BP3_TARGET` -> cwd git toplevel -> `BP3_SELF_ROOT`!). Wait: passing `BP3_ROOT="${BP3_ROOT:-$root}"` for `q`/`config`/`harness`/etc. preserves `test/config.sh:41` (`"$work/nogit/bin/bp3" config` fails outside git even when cwd is inside a git repo), while `BP3_TARGET` + `BP3_SELF_ROOT` handle `skills`/`init` identically to today!
- **Retired `g` door (`test/g.sh:46`, `test/hooks.sh`):** Keep `g hooks` fail-open (drains stdin, prints `"bp3 g was renamed to bp3 q; re-run bp3 skills install"` on stderr, exits `0`) and any other `g ...` exits `2` (`main.ml` AND dev stub when binary is missing).
- **Unknown verb / `-h` / `--help` / `--version`:**
  - `bp3 --version` prints `<bp3_version>\n` (exit `0`).
  - `bp3 -h` / `bp3 --help` prints the unified `usage_text` + `'  bp3 q -h for quest/node doors'` (exit `0`), matching `test/completion.sh` / `test/diagram.sh`.
  - Unknown top-level verb prints `usage_text` on stderr and exits `2` (preserving `test/g.sh:47` `quest` rejection).
- **`test/mode.sh:22-23`:** Currently parses `CORE_SKILLS=` and `DEV_SKILLS=` from `bin/bp3` with `sed`. Update `test/mode.sh` to check skill sets via `bp3` (or read them from `src/skills/skills.ml`, keeping `test/unit/test_skills.ml` as the authoritative OCaml check).
- **`scripts/check-retired-terms.sh:67`:** Update the allowlist so only `src/skills/skills.ml` (not `bin/bp3`) is exempt for retired workflow/skill names.
- **Note on `test/install.sh` & `test/release-sync.sh` during `cli.1`:** Until `install.1` updates `scripts/install-bp3.sh`, `install-bp3.sh` still copies `bin/bp3` and `bp3-q`. Because `cli.1`'s thin stub does NOT fall back to `PATH` `bp3-q` unless handled — **wait: verify `test/install.sh` and `test/release-sync.sh` pass in `cli.1`!** In `cli.1`, while `scripts/install-bp3.sh` still installs `$prefix/bin/bp3` + `$prefix/bin/bp3-q`, the thin stub can check `sibling="$root/bin/bp3-q"` (strictly sibling, NEVER `PATH`) as a 1-line transitional fallback in `cli.1`, and `install.1` removes that line when `install-bp3.sh` switches to copying the binary directly to `$prefix/bin/bp3`! That guarantees `make check-full` is **100% 25/25 green** on `cli.1`'s own commit!
- **Tests:**
  - *Known cases:* `test/unit/test_main.ml` tests `--version`, `-h`, `init`, `skills`, `g` dispatch; `test/skills.sh`, `test/mode.sh`, `test/hooks.sh`, `test/config.sh`, `test/g.sh`, `test/completion.sh` all pass unmodified (except `test/mode.sh:22-23`).
  - *Property-based:* Inherited from `test/unit/test_skills.ml` + existing `test_hooks.ml` / `test_main.ml` QCheck2 suites.
