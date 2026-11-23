---
date: 2026-11-22
quest: ../../QUEST.md
node: build.1
status: proposed
---

# build.1 - build-id: the engine knows its commit

## TL;DR

The engine says which commit it was built from. A dune rule runs
`scripts/build-id` at build time and compiles the result into
`Build_info.build`: `<bp3_version>+<sha7>`, plus `-dirty` when the tree
has tracked changes, or `<bp3_version>+unknown` outside git.
`bp3-q --build` prints it and `bp3 config` carries it as `build`.
`--version` is unchanged.

## Acceptance gates

Observed today:

```text
$ ./_build/default/src/quest/main.exe --build
{"ok":false,"error":{"code":"E_USAGE",...}}
$ ./bin/bp3 config | jq -r .build
null
```

Design trace:

```text
$ dune build src/quest/main.exe && ./_build/default/src/quest/main.exe --build
0.2.0+e79a73a
$ echo x >> README.md && dune build src/quest/main.exe && ./_build/default/src/quest/main.exe --build
0.2.0+e79a73a-dirty
$ ./bin/bp3 config | jq -r .build
0.2.0+e79a73a
$ ./bin/bp3 q --version
0.2.0
$ (tarball, no .git) scripts/build-id
0.2.0+unknown
```

```yaml
objective: every bp3-q binary can name the bp3 commit it was built from
prove by:
  - test/unit: Build_info.build matches ^[0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7}(-dirty)?|unknown)$ and starts with Gitx.bp3_version
  - test/release.sh (or a new block): a fixture repo -> scripts/build-id clean = 0.2.0+<sha7>; tracked edit -> -dirty;
    untracked file only -> no -dirty; outside git -> +unknown
  - bp3-q --build == scripts/build-id run in the same tree; bp3 config .build the same
  - test/release.sh line 41 (--version prints exactly the constant) unchanged and green
  - make check-full
done when: --build prints the build id in a clean, a dirty and a no-git tree, config carries it, and each check fails on master
```

## Diagram

```text
git HEAD + tracked diff ──► scripts/build-id ──► (dune rule) build_info.ml ──► Build_info.build
                                                                                 │
                                       bp3-q --build ◄───────────────────────────┤
                                       bp3 config .build ◄───────────────────────┘
```

## Pseudocode

```python
# scripts/build-id (bash in the real thing)
def build_id(root):
    v = sed("bp3_version = \"(.*)\"", root / "src/quest/gitx.ml")
    sha = git("rev-parse", "--short=7", "HEAD") or None
    if sha is None:
        return f"{v}+unknown"
    dirty = git_rc("diff", "--quiet", "HEAD", "--") != 0   # tracked changes only
    return f"{v}+{sha}" + ("-dirty" if dirty else "")

# src/quest/dune
# (rule (targets build_info.ml) (deps (universe) %{project_root}/scripts/build-id)
#  (action (with-stdout-to build_info.ml (run bash %{dep:...} --ml))))
#   --ml prints: let build = "0.2.0+e79a73a"
```

## Tables

| Field | Value |
|---|---|
| Intent | name the engine's commit, so drift can be seen downstream |
| Lane | standard |
| Output | `scripts/build-id` (new), `src/quest/dune` (rule), `src/quest/main.ml` (`--build`, `config .build`), `src/quest/names.ml` (`flag_build`), tests |
| Acceptance | `--build` and `config .build`; fail today (`E_USAGE`, `null`) |
| Depends on | none |

| Tree | Build id |
|---|---|
| clean HEAD | `0.2.0+<sha7>` |
| tracked change (staged or not) | `0.2.0+<sha7>-dirty` |
| untracked files only | `0.2.0+<sha7>` |
| no git (tarball) | `0.2.0+unknown` |

## Prose

Every engine since 2026-11-14 says `0.2.0`, so the version tells nobody
anything: the installed one is 263 commits behind master and looks the
same. A version bump per promotion would fix it if anyone remembered;
nobody has. A build id from git is free to keep current.

`(universe)` makes dune re-run the rule on every build. That is cheap
(one `git rev-parse`, one `git diff --quiet`) and dune only relinks when
`build_info.ml`'s content changes, so a clean incremental build stays
incremental. The rule runs inside `_build/default/src/quest`; git finds
the repo by walking up, in a desk too.

`-dirty` counts tracked changes only. Untracked files don't change what
was compiled unless dune picked them up, and counting them would mark
every build in a tree with a stray scratch file.

`--version` keeps printing the bare constant: `test/release.sh:41` and
`install-bp3.sh`'s `old=` line read it, and the version guard compares
it. The build id is a second fact, not a new version scheme.

## Tests

Known cases: the four tree states above in a fixture repo, plus `--build`
equal to the script in the same tree and `--version` unchanged.
Property-based: omitted. The input space is those four git states, and
all four are enumerated.
