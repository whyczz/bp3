---
date: 2026-11-24
quest: ../../QUEST.md
node: compat.1
status: proposed
---

# compat.1 - install-hook-and-test-isolation: closing red-chair hardening for test/skills.sh, spaces in repo names, and library decoupling

## TL;DR

Address both major findings from the closing red chair before building `ticket.1`: (1) ensure `test/skills.sh` (which creates a git repo literally named `"project with spaces"` and copies only `bin/bp3` without `_build/`) and `test/mode.sh` run cleanly both under `make check-full` AND standalone even when an older pre-install `bp3-q` sits on `PATH` (by exporting `BP3_Q_BIN` to the repo's built `main.exe` and a per-script temp `BP3_DB` when unset), and (2) assert that `src/db/dune` and `src/repo/dune` have zero dependency on `bp3_quest`.

## Acceptance gates

Observed today:

```text
$ grep -n "BP3_DB\|BP3_Q_BIN" test/skills.sh test/mode.sh
(no matches)
$ grep -n "project with spaces" test/skills.sh
19:mkdir -p "$work/project with spaces/bin" "$work/project with spaces/scripts"
```

Design trace:

```text
# Simulate older v0.3.0 bp3-q on PATH that does not know `repo`:
$ fakebin="$(mktemp -d)"
$ printf '#!/bin/sh\necho "unknown door" >&2; exit 2\n' > "$fakebin/bp3-q"
$ chmod +x "$fakebin/bp3-q"
$ PATH="$fakebin:$PATH" ./test/skills.sh
  -> rc 0 ("project with spaces" registers as project-with-spaces in temp BP3_DB!)
$ PATH="$fakebin:$PATH" ./test/mode.sh
  -> rc 0 (real ~/.local/share/bp3/bp3.sqlite untouched!)
$ grep -n "bp3_quest" src/db/dune src/repo/dune
  -> (no matches)
$ make check-full
  -> rc 0
```

```yaml
objective: prove fail-fast skills_install() auto-registration passes test/skills.sh and test/mode.sh standalone and under stale PATH bp3-q, with zero bp3_quest dependency in bp3_db/bp3_repo
prove by:
  - PATH="<fake-old-bp3-q>:$PATH" ./test/skills.sh && PATH="<fake-old-bp3-q>:$PATH" ./test/mode.sh
  - dune test (test/unit/test_repo.ml explicit "project with spaces" -> "project-with-spaces" regression)
  - test ! "$(grep -E 'bp3_quest' src/db/dune src/repo/dune)"
  - make check-full (verifying real ~/.local/share/bp3/bp3.sqlite mtime unchanged)
done when: standalone suites pass with a stub stale bp3-q on PATH, spaces-in-name regression passes, and make check-full is green
```

## Diagram

```text
standalone ./test/skills.sh or ./test/mode.sh
  ├── export BP3_DB="${BP3_DB:-$work/bp3.sqlite}"           (never touches real ~/.local/share/bp3/bp3.sqlite!)
  ├── export BP3_Q_BIN="${BP3_Q_BIN:-$repo/_build/.../main.exe}"  (never hits stale ~/.local/bin/bp3-q!)
  └── "$root/bin/bp3" skills install  (inside "project with spaces")
         └──► repo add "$work/project with spaces" -> slug "project-with-spaces" -> ok!
```

## Pseudocode

```python
# In test/skills.sh and test/mode.sh (near top, after $work = mktemp -d):
export_if_unset("BP3_DB", f"{work}/bp3.sqlite")
export_if_unset("BP3_Q_BIN", f"{repo}/_build/default/src/quest/main.exe")

# Regression check:
assert slugify("project with spaces") == "project-with-spaces"
assert "bp3_quest" not in read_file("src/db/dune")
assert "bp3_quest" not in read_file("src/repo/dune")
```

## Tables

| Field | Value |
|---|---|
| Intent | close both major findings from the `/red-ink` closing red chair (`test/skills.sh` spaces + stale `PATH` `bp3-q` + `bp3_db`/`bp3_repo` decoupling) |
| Lane | micro |
| Output | `test/skills.sh`, `test/mode.sh`, `test/unit/test_repo.ml` (`"project with spaces"` golden regression) |
| Acceptance | fails today (`test/skills.sh` and `test/mode.sh` lack `BP3_DB`/`BP3_Q_BIN` isolation); passes when standalone suites pass under a stub stale `bp3-q` on `PATH` and `make check-full` passes |
| Depends on | `repo.1 - repo-registry` |
| Must not touch | `refs/heads/bp3/*`, `skills/*` |

## Prose

Added from the 2026-11-24 closing red chair of `2026-11-23-sqlite-control-plane`. Without this node, `repo.1`'s fail-fast `skills_install()` hook would break `test/skills.sh:67` during grading whenever `~/.local/bin/bp3-q` is still on `v0.3.0`, because `test/skills.sh:21` copies `bin/bp3` into a temp dir without `_build/` and creates a fixture directory literally named `"project with spaces"`.

Edge cases:
- **Pre-build check in `test/skills.sh`:** If `BP3_Q_BIN` points to an unbuilt `_build/.../main.exe`, fail clearly with `build first: dune build src/quest/main.exe` (matching `test/mode.sh:15`).
- **Pre-existing `BP3_DB` set by `run_suites.ml`:** Using `${BP3_DB:-$work/bp3.sqlite}` honors `run_suites.ml`'s per-suite temp DB when run via `make check-full`, while also isolating standalone `./test/skills.sh` runs.

## Tests

- **Known cases:** `"project with spaces"` → `"project-with-spaces"` unit regression; standalone `./test/skills.sh` and `./test/mode.sh` under a fake failing `bp3-q` on `PATH`; real `~/.local/share/bp3/bp3.sqlite` untouched check.
- **Property-based:** omitted here — `Db.slugify` property coverage lives in `repo.1`'s QCheck2 generator (`test/unit/test_repo.ml`).
