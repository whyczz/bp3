---
node: install.1
slug: retire-bp3-q-and-single-binary-install
kind: code
lane: standard
status: proposed
depends_on:
  - cli.1 - wire-single-cli-and-thin-self-stub
---

# install.1 - retire-bp3-q-and-single-binary-install

TL;DR
Switch `scripts/install-bp3.sh` and `Makefile` to build and install one single compiled `$PREFIX/bin/bp3` binary (removing any stale `$PREFIX/bin/bp3-q`), remove the transitional sibling `bp3-q` line from `./bin/bp3`, delete dead `scripts/bp3-shim`, and update `test/install.sh`, `test/release-sync.sh`, and `test/agy-statusline.sh` to verify single-binary host mode end-to-end.

## Acceptance gates

Design trace:

```text
# 1. Pre-plant stale $PREFIX/bin/bp3-q, run install-bp3.sh -> single binary installed, stale bp3-q removed
$ PREFIX=$work/prefix scripts/install-bp3.sh $work/dist/bp3-v0.13.0-darwin-arm64
installed bp3 0.13.0 -> .../prefix/bin/bp3 (was: none)
installed bp3 skills -> .../prefix/share/bp3/skills
installed global bp3 skills + hooks -> ...

$ test -x "$work/prefix/bin/bp3" && ! head -c 2 "$work/prefix/bin/bp3" | grep -q '#!'
$ test ! -e "$work/prefix/bin/bp3-q"
$ test ! -e scripts/bp3-shim

# 2. Full host-repo dogfood with ONLY $work/prefix/bin/bp3 on PATH (zero bp3-q anywhere)
$ PATH="$work/prefix/bin:$PATH" bp3 --version
0.13.0
$ PATH="$work/prefix/bin:$PATH" bp3 init-repo
{"ok":true,"manifest":"backpack.toml","manifest_created":true,...}
$ PATH="$work/prefix/bin:$PATH" bp3 q c dogfood && bp3 skills check

# 3. Zero bp3-q references in bin/bp3, scripts/, Makefile, test/install.sh, test/release-sync.sh, test/agy-statusline.sh
$ make check-full
run-suites: ok 25/25
```

Runnable goal block:
- **objective:** Complete the transition to a single installed `$PREFIX/bin/bp3` binary with zero `bp3-q` and zero bash wrapper in installed prefixes.
- **prove by:** `test/install.sh`, `test/release-sync.sh`, `test/agy-statusline.sh`, and `make check-full`.
- **done when:** `make check-full` passes 25/25 suites, `scripts/bp3-shim` is deleted, `$PREFIX/bin/bp3` is a compiled binary, stale `$PREFIX/bin/bp3-q` is removed on install, and host-repo commands run end-to-end with zero `bp3-q`.

## Diagram

```text
make release
  -> dist/bp3-v<ver>-<os>-<arch> (+ .sha256)
          |
          v
scripts/install-bp3.sh
  |-- rm -f $PREFIX/bin/bp3-q $PREFIX/bin/bp3
  |-- cp $artifact $PREFIX/bin/bp3          (ONE compiled OCaml binary!)
  |-- cp skills/, scripts/{check-skills,agy-statusline}, completions/ -> $PREFIX/share/bp3/
  |-- stamp $PREFIX/share/bp3/RELEASE (when HEAD == annotated tag v<ver>)
  |-- "$PREFIX/bin/bp3" skills install --global --harness=all
  +-- wire agy statusLine -> $PREFIX/share/bp3/scripts/agy-statusline
```

## Pseudocode

```python
def install_bp3(prefix: str, artifact: str | None) -> None:
    # Default artifact: dist/bp3-v{version}-{os}-{arch}
    # Download fallback from gh release: try bp3-v* first, then legacy bp3-q-v*
    old = read_version(f"{prefix}/bin/bp3") or read_version(f"{prefix}/bin/bp3-q") or "none"
    rm_f(f"{prefix}/bin/bp3-q", f"{prefix}/bin/bp3")
    cp(artifact, f"{prefix}/bin/bp3")
    chmod_x(f"{prefix}/bin/bp3")
    sync_share_dir(prefix)  # skills, scripts/{check-skills,agy-statusline}, completions, RELEASE
    if not env.get("BP3_SKIP_GLOBAL_SKILLS") == "1":
        run([f"{prefix}/bin/bp3", "skills", "install", "--global", "--harness=all"])
    wire_agy_statusline(prefix)
```

## Fields

| Field | Value |
|---|---|
| Intent | Retire `$PREFIX/bin/bp3-q`, `scripts/bp3-shim`, and the installed bash wrapper so `install-bp3.sh` ships one compiled `bp3` binary |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `scripts/install-bp3.sh`, `Makefile`, `bin/bp3` (drop transitional sibling `bp3-q` line), deleted `scripts/bp3-shim`, updated `test/{install,release-sync,agy-statusline}.sh` |
| Acceptance | Fails today (`install-bp3.sh` still installs `bp3-q` + bash `bp3`, `scripts/bp3-shim` exists); passes when single-binary install, stale `bp3-q` removal, host dogfood, and `make check-full` (25/25) pass |
| Depends on | `cli.1 - wire-single-cli-and-thin-self-stub` |

## Prose & edge cases

- **Upgrade from `v0.13.0` (`bp3-q` cleanup):** Users upgrading from `v0.13.0` already have `~/.local/bin/bp3` (bash) and `~/.local/bin/bp3-q` (OCaml). `scripts/install-bp3.sh` reads `old` from `$prefix/bin/bp3 --version` first and falls back to `$prefix/bin/bp3-q --version`, then runs `rm -f "$prefix/bin/bp3-q" "$prefix/bin/bp3"` before installing the single compiled `$prefix/bin/bp3` — ensuring no stale `bp3-q` lingers on `PATH`.
- **Release artifact naming (`Makefile:49`):** Change `RELEASE_ARTIFACT` from `dist/bp3-q-v...` to `dist/bp3-v...`. In `scripts/install-bp3.sh`, keep `gh release download` trying `bp3-v$version-$os-$arch*` first (and falling back to `bp3-q-v...` if downloading an older tag).
- **`bp3 release` self-mode auto-install (`src/quest/release_io.ml:161`):** `release_io.ml` passes `BP3_RELEASE_ARTIFACT` (pointing directly to `_build/default/src/quest/main.exe` or `dist/...`) as `$1` to `scripts/install-bp3.sh`, so `bp3 release` works seamlessly without needing changes to `release_io.ml`.
- **Self-mode `./bin/bp3` final cleanup:** Remove the 1-line transitional `$root/bin/bp3-q` fallback added in `cli.1` so `git grep bp3-q -- bin/ scripts/ Makefile` returns **zero** active references (only the `rm -f "$prefix/bin/bp3-q"` cleanup + legacy download fallback in `scripts/install-bp3.sh`).
- **Tests (`test/install.sh`, `test/release-sync.sh`, `test/agy-statusline.sh`):**
  - *Known cases:* (1) pre-planted stale `$prefix/bin/bp3-q` is deleted by `install-bp3.sh` and `was: <old>` is reported accurately; (2) `$prefix/bin/bp3` is a compiled binary (not a `#!` script); (3) `bp3 --version`, `bp3 init-repo`, `bp3 q ...`, `bp3 q hooks`, `bp3 skills install|check|prune-local`, and `agy-statusline` all work in a host repo with ONLY `$prefix/bin/bp3` on `PATH` and zero `bp3-q`.
  - *Property-based:* Omitted (shell packaging & install fixture verification; pure OCaml invariants are covered by QCheck2 in `test/unit/test_skills.ml`).
