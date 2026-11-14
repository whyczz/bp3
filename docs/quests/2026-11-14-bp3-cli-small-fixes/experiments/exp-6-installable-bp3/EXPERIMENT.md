---
date: 2026-11-14
quest: ../../QUEST.md
exp: 6
status: proposed
---

# Exp 6 — Installable bp3: dogfooding in another repo

## TL;DR

bp3 becomes usable from a repo that is not this one:
`make install` copies the Exp 5 release artifact — from
`dist/` in this repo, or fetched from the GitHub Release
(`gh release download`) when no checkout is at hand — to
`~/.local/bin/bp3-q` (prefix overridable), checksum
verified either way —
never a symlink into `_build`, so a rebuild here never
silently changes the binary esc3 is running; re-running
install after a new release is the upgrade, and it prints
old → new versions. A thin `bp3` shim beside it execs
`bp3-q` with the **caller's** repo as root (cwd, honoring
`BP3_ROOT` when set) — the home wrapper's forced
`BP3_ROOT=<bp3 repo>` behavior is the bug this replaces for
cross-repo use. `bp3-q init-repo` (name settled here:
a `q` door verb companion, spelled like the wrapper's
existing `bp3 init` but repo-scoped) scaffolds what a fresh
repo needs: `plans/default.yaml` + `plans/direct.yaml`
copied from the release's bundled plans, and nothing else —
quest folders/branches are then created by `q c` as usual.

Acceptance is a dogfood: in a scratch repo standing in for
esc3, from a different cwd, a quest + exp are created,
submitted, and read back using only the installed binary.

Added at framing, 2026-11-14. Depends on Exp 5: installs
consume release artifacts, never `_build` output.

## Demo (design trace)

```text
$ make install                       # in bp3, after `make release`
installed bp3-q 0.2.0 -> ~/.local/bin/bp3-q   (was: none)
$ cd ~/src/esc3 && bp3-q --version
0.2.0
$ bp3-q init-repo
wrote plans/default.yaml, plans/direct.yaml (bp3 0.2.0)
$ bp3 q c my-first-quest && bp3 q my-first-quest c exp-1-try
{"ok":true, ...}                       (state lives in esc3's refs, bp3 repo untouched)

# after bp3 0.3.0 ships:
$ make install
installed bp3-q 0.3.0 -> ~/.local/bin/bp3-q   (was: 0.2.0)
```

Today (observed): no `make install`; running this repo's
`bin/bp3 q …` from another cwd operates on **this** repo
(wrapper forces `BP3_ROOT` home, `bin/bp3:146-148`);
`bp3-q` does not exist on PATH.

## Diagram

```text
this repo ── make release ──► dist/bp3-q-v<ver>-<os>-<arch> ── make install ──► ~/.local/bin/bp3-q (copy)
                                                                                    │ exec, BP3_ROOT unset
esc3:  bp3 q ... ──► shim: root = cwd ──► bp3-q ──► git -C esc3, plans from esc3/plans/
esc3:  bp3-q init-repo ──► esc3/plans/{default,direct}.yaml   (once; refuses to overwrite differing files)
upgrade: new release ──► make install again ──► copy replaced, old->new printed; Exp 5 guard covers skewed repos
```

## Pseudocode

```python
def install(prefix="~/.local/bin"):
    art = latest_release_artifact()              # Exp 5 output, checksum verified first
    old = version_of(prefix/"bp3-q")             # --version, or "none"
    copy(art, prefix/"bp3-q"); chmod_x()
    print(f"installed bp3-q {art.version} -> {prefix}/bp3-q (was: {old})")

def init_repo(root):
    for p in ["plans/default.yaml", "plans/direct.yaml"]:
        if exists(root/p) and differs(bundled(p)): refuse(p)   # never clobber a repo's own plan
        write(root/p, bundled(p))
```

## Tables

| Field | Value |
|---|---|
| Intent | run bp3 in esc3 (or any repo) with a known binary version, without touching this repo's state |
| Lane | standard |
| Output | `install` target in `Makefile`; `bp3-q` shim + `init-repo` in the CLI/wrapper seam; bundled plans beside the artifact; dogfood fixture script |
| Acceptance | cases below; the headline case fails today (observed above) |
| Depends on | Exp 5 (release artifacts + `--version` + version-ahead guard) |

| Case | Expected after |
|---|---|
| fresh `make install` | `bp3-q` on PATH runs `--version` from any cwd; printed version matches the release artifact |
| esc3 dogfood (scratch repo) | `init-repo`, quest + exp create, submit, read — all state in the scratch repo's refs; `git -C <bp3 repo> for-each-ref` unchanged |
| wrapper trap removed | running the installed `bp3 q` from esc3 never writes to the bp3 repo (asserted by ref listing before/after) |
| upgrade | second `make install` after a version bump prints old → new; older release artifact still in `dist/` for rollback |
| skewed repo (newer stamps, older installed binary) | Exp 5 guard fires: reads warn, writes refuse — no special-casing here |
| `init-repo` over existing differing `plans/` | refuses per-file, names the conflict, writes nothing |
| `_build` deleted in bp3 repo | installed `bp3-q` keeps working (it is a copy, not a link) |

## Acceptance test (goal block)

- **Objective:** a second repo runs the full quest loop on
  an installed, versioned bp3, and upgrades are boring.
- **Prove by:** the dogfood fixture — scratch git repo,
  installed binary only, full create/submit/read trace;
  bp3-repo ref listing diffed around every step; upgrade
  trace after a fixture version bump; `make check` green.
- **Done when:** dogfood passes with zero writes to the
  home repo, upgrade prints old → new, and deleting
  `_build` changes nothing for the installed binary.

## Prose

Context: the owner asked how bp3 gets accessed once
dogfooding starts in esc3. The investigation found the
binary already portable (`root` = `BP3_ROOT` or cwd,
`src/quest/gitx.ml:23`; plans under `<root>/plans/`,
`src/quest/store.ml:73`) and only the wrapper home-bound —
so this exp is distribution and root resolution, not a
port. Why a copy, never a symlink into `_build`: a symlink
makes every `dune build` in this repo a silent, unversioned
upgrade of the binary another repo's state depends on —
the exact failure Exp 5's version guard exists to catch,
arriving through the back door. Why `init-repo` refuses to
overwrite differing plans: a repo's plan is its quest_type
contract; an installer that clobbers it to "help" would be
indistinguishable from corruption. Rollback is deliberately
dumb: old artifacts stay in `dist/`, reinstall one by path.
Out of scope: publishing anywhere (no registry, no CI),
Windows, and multi-version side-by-side installs — one
installed version, named by `--version`, is the pattern
until a second concurrent version is actually needed.

## Tests

unit: none (install/root plumbing; fixture-shaped) ·
fixtures: the esc3 dogfood script (scratch repo, full
loop, home-ref diff), install/upgrade/idempotence cases,
`init-repo` refusal case, in the repo's test home ·
demos: the traces above against a real second repo at
review
