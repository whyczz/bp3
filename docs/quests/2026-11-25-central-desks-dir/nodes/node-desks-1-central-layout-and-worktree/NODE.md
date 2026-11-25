---
date: 2026-11-25
quest: ../../QUEST.md
node: desks.1
status: active
---

# desks.1 - central-layout-and-worktree: move desks and metadata to `~/.bp3/desks/<repo>-<hash8>/{quests,runs,.meta}`

## TL;DR

Replace repo-nested `.bp3/worktrees/` and `.bp3/desks/` with one central machine-local directory (`$BP3_DESKS_DIR` or `~/.bp3/desks/`) bucketed by `<repo_slug>-<hash8>` of the repo's canonical `git_common_dir`, storing quest desks under `quests/<quest>`, node/grade desks under `runs/<quest>/<node>/<run_id>` (siblings — never nested!), and `<run_id>.json` metadata under `.meta/`. Keep read+release fallback for legacy `<main_root>/.bp3/desks/*.json` (never writing there), unify `Config.list_desks` onto `Worktree.load_records ()`, update `test/unit/test_layout.ml` with known cases + QCheck2 properties, and update `test/worktree.sh` and `test/config.sh` with `BP3_DESKS_DIR` isolation and `bp3 harness desk` parity checks.

## Acceptance gates

Observed today (2026-11-25, `c8bfbb9`):

```text
$ ./bin/bp3 harness desk derive demo node-a R1
{"ok":true,"path":".bp3/worktrees/demo/node-a/R1"}
$ rg -n '\.bp3/desks' src/quest/worktree.ml src/quest/config.ml
src/quest/config.ml:35:  let d = Filename.concat root ".bp3/desks" in
src/quest/worktree.ml:174:let desks_dir = Filename.concat root ".bp3/desks"
```

Design trace:

```text
$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk derive demo node-a R1
{"ok":true,"path":"/tmp/d/bp3-<8hex>/runs/demo/node-a/R1"}
$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare --quest q1
{"ok":true,"run_id":"quest-q1","quest":"q1","node":"(quest)","path":"/tmp/d/bp3-<8hex>/quests/q1","ref":"quest/q1",...}
$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare q1 node-1 --run grade-n1-c1-a1 --commit HEAD
{"ok":true,"run_id":"grade-n1-c1-a1","path":"/tmp/d/bp3-<8hex>/runs/q1/node-1/grade-n1-c1-a1",...}
# zero files created under <repo>/.bp3/
# quest desk git status stays clean while grade desk is open
# desk list / desk exit / bp3 config from inside either desk resolve the same repo_key bucket
# legacy <main_root>/.bp3/desks/OLD.json appears in desk list and is deleted on desk release --run OLD
$ dune test && ./test/worktree.sh && ./test/config.sh && make check-full
# rc 0
```

```yaml
objective: move all new desks and desk metadata to central $BP3_DESKS_DIR (~/.bp3/desks)/<repo>-<hash8>/{quests,runs,.meta} anchored on canonical git_common_dir, with sibling quest/run paths and legacy .bp3/desks/ read+release fallback
prove by:
  - test/unit/test_layout.ml: unit cases + QCheck2 properties for repo_key (collision-free across same-named repos), desks_base_of (BP3_DESKS_DIR vs HOME), quest_desk_dir vs run_desk_dir non-nesting invariant, and legacy constants
  - test/worktree.sh (with BP3_DESKS_DIR="$work/desks"): central derive/prepare/check/exit/release/list, parallel 5-way prepare (.meta/*.json), orphan detection (runs/ and quests/), sibling quest+grade desk non-nesting, zero <repo>/.bp3/ creation, legacy .bp3/desks/ read+release transition, and bp3 harness desk parity
  - test/config.sh (with BP3_DESKS_DIR="$work/desks"): bp3 config returns identical desks from main checkout and from inside a worktree
  - make check && make check-full (25/25 suites)
done when: all unit and fixture checks pass, zero new desks or metadata are ever written under <repo>/.bp3/, and existing open .bp3/desks/ records still list and release cleanly
```

## Diagram

```text
$BP3_DESKS_DIR (or $HOME/.bp3/desks)
  └── <repo_slug>-<hash8>/                    ◄── keyed by canonical git_common_dir
        ├── .meta/
        │     ├── quest-<q>.json              ◄── Unix.link exclusive publish
        │     └── <run_id>.json
        ├── quests/
        │     └── <q>/                        ◄── quest desk (branch quest/<q>)
        └── runs/
              └── <q>/<node>/<run_id>/        ◄── node/grade desk (sibling, never nested in quests/<q>!)

Read/release fallback (read-only on legacy, never written):
  <main_root>/.bp3/desks/<run_id>.json  ──► visible in desk list/check, unlinked on release
```

## Pseudocode

```python
# src/quest/layout.ml (pure, zero I/O)
def sanitize_repo_slug(name: str) -> str:
    # lowercase ASCII [a-z0-9-], collapse/strip '-' edges, fallback "repo"
    ...

def repo_key(repo_name: str, canon_common_dir: str) -> str:
    slug = sanitize_repo_slug(repo_name)
    hash8 = md5_hex(canon_common_dir)[:8]  # OCaml stdlib Digest.to_hex (Digest.string ...)
    return f"{slug}-{hash8}"

def desks_base_of(env_desks: str | None, home: str | None) -> str:
    if env_desks and env_desks != "":
        return strip_trailing_slash(env_desks)
    return f"{strip_trailing_slash(home or '')}/.bp3/desks"

def repo_desks_dir(base: str, key: str) -> str:
    return f"{base}/{key}"

def quest_desk_dir(repo_dir: str, quest: str) -> str:
    return f"{repo_dir}/quests/{quest}"

def run_desk_dir(repo_dir: str, quest: str, node: str, run_id: str) -> str:
    return f"{repo_dir}/runs/{quest}/{node}/{run_id}"

def desks_meta_dir(repo_dir: str) -> str:
    return f"{repo_dir}/.meta"

# src/quest/worktree.ml (I/O)
def main_root() -> str:
    common = git_common_dir()
    if common and basename(common) == ".git":
        return canon(dirname(common))
    return canon(root)

def current_repo_desks_dir() -> str:
    common = canon(git_common_dir() or root)
    name = basename(main_root())
    key = Layout.repo_key(name, common)
    return Layout.repo_desks_dir(desks_base(), key)

# load_record(run_id): check central .meta/<run_id>.json first, then <main_root>/.bp3/desks/<run_id>.json
# load_records(): merge central + legacy (dedup by run_id, central wins, sorted)
# save_record(r): ONLY writes to central .meta/<run_id>.json via Unix.link
# delete_record(run_id): unlink central .meta/<run_id>.json AND legacy <main_root>/.bp3/desks/<run_id>.json if present
# Config.list_desks(): call Worktree.load_records () directly (no duplicate .bp3/desks reader!)
```

## Tables

| Field | Value |
|---|---|
| Intent | move all desk worktrees and `.meta/` records out of `<repo>/.bp3/` into central `$BP3_DESKS_DIR` (`~/.bp3/desks`)/`<repo>-<hash8>/{quests,runs,.meta}` anchored on `git_common_dir` |
| Lane | high-blast-radius |
| Output | `src/quest/layout.ml`, `src/quest/worktree.ml`, `src/quest/config.ml`, `src/warden/warden_io.ml` (comment only), `test/unit/test_layout.ml`, `test/worktree.sh`, `test/config.sh` |
| Acceptance | fails today (`derive` returns `.bp3/worktrees/...`, `worktree.ml` & `config.ml` hardcode `root/.bp3/desks`); passes when central paths, non-nesting, legacy fallback, and all unit + fixture suites pass |
| Depends on | none |
| Must not touch | `Makefile`, `scripts/check-gates`, `src/quest/metrics_io.ml`, `skills/*`, `CONSTRAINTS.md` |

## Prose

Why `Digest.string` (MD5 8-hex prefix) for `repo_key`: `Digest` is in OCaml's standard library (zero new dependencies under `CONSTRAINTS.md`), purely deterministic, and 8 hex chars (32 bits) over canonical `git_common_dir` prevents collisions between same-named repos (e.g., `~/m/app` vs `~/work/app`) while keeping directory paths readable in terminal prompts and `git worktree list`.

Why `main_root ()` for legacy fallback and `abs_path`: legacy `.bp3/desks/<run_id>.json` records store relative paths like `.bp3/worktrees/demoq`. Resolving relative `r.r_path` against `main_root ()` (instead of `root`) means even a legacy desk still resolves and releases cleanly if you invoke `bp3 harness desk release` from inside a worktree. Absolute paths (all new central desks and `--path` overrides) pass through unchanged.

Also verify `do_exit`: `conductor_path` in its JSON verdict should return `main_root ()` (the main checkout path) rather than `canon root` so exiting a desk when invoked via `cd "$desk" && bp3 worktree exit` points back to the real conductor repo even when `BP3_ROOT` is unset!

## Tests

- **Known cases (`test/unit/test_layout.ml`):** `sanitize_repo_slug` (spaces, uppercase, dots, empty -> `"repo"`), `repo_key` stability and distinct hashes for `/a/bp3/.git` vs `/b/bp3/.git`, `desks_base_of` precedence (`Some "/custom/"` vs `None` with `HOME="/u/me"`), `quest_desk_dir`, `run_desk_dir`, `desks_meta_dir`, and `legacy_desks_root = ".bp3/worktrees"`.
- **Property-based (QCheck2 in `test/unit/test_layout.ml`):** for any valid `(quest, node, run_id)`, `run_desk_dir` is NEVER equal to and NEVER starts with `quest_desk_dir ^ "/"` (non-nesting law), and `repo_key` always matches `^[a-z0-9-]+-[0-9a-f]{8}$`.
- **Fixture tests (`test/worktree.sh`, `test/config.sh`):** isolated via `BP3_DESKS_DIR="$work/desks"`; verify central paths, zero `.bp3/` created in `$work/repo`, concurrent quest+grade desk leaves quest desk `git status` clean, `bp3 harness desk` parity (`prepare`/`list`/`release`), calling `desk list`/`exit` and `bp3 config` from inside a worktree returns identical desks, and planted legacy `.bp3/desks/LEGACY.json` lists and releases cleanly.
