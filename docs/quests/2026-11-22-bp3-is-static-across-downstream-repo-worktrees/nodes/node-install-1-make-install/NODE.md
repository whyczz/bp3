---
date: 2026-11-22
quest: ../../QUEST.md
node: install.1
status: proposed
---

# install.1 - make-install: one command installs HEAD's build

## TL;DR

`make install` builds `main.exe` at HEAD and installs all three pieces
(`bin/bp3-q`, `bin/bp3`, `share/bp3/`) plus the zsh completion, from a
tree with no tracked changes, with no tag and no `dist/`. It writes the
build id to `share/bp3/BUILD`, the bp3 main checkout and full commit to
`share/bp3/SOURCE` (install.3 reads both; `BP3_REPO_HOME` overrides
`SOURCE`'s repo at read time), and prints what it replaced.
It is now the
only bp3 command that writes outside a repo: `bp3 init` and
`bp3 skills install` stop copying the completion into a shared dir.
`make release` and `make publish` keep the tagged path.

## Acceptance gates

Observed today:

```text
$ make install PREFIX=$S
install: no artifact .../dist/bp3-q-v0.2.0-darwin-arm64; run make release first
$ make release
release-check: tag v0.2.0 at fcfce07…, HEAD is e79a73a…
$ HOME=$S/home bp3 init            # with $S/home/.zsh/completions present
installed _bp3 -> $S/home/.zsh/completions/_bp3
```

Design trace:

```text
$ make install PREFIX=$S
installed bp3 0.2.0+e79a73a -> $S (was: none)
$ $S/bin/bp3-q --build; cat $S/share/bp3/BUILD; scripts/build-id
0.2.0+e79a73a
0.2.0+e79a73a
0.2.0+e79a73a
$ cmp bin/bp3 $S/bin/bp3 && diff -r skills $S/share/bp3/skills && echo same
same
$ cat $S/share/bp3/SOURCE        # run from a desk too: repo is the main checkout, never the desk
{"repo":"/Users/whycz/m/bp3","commit":"e79a73a…"}
$ echo x >> README.md; make install PREFIX=$S
install: the tree has tracked changes; commit first      (exit 1; $S unchanged)
$ git checkout README.md; git commit --allow-empty -qm next; make install PREFIX=$S
installed bp3 0.2.0+<new sha7> -> $S (was: 0.2.0+e79a73a)
$ HOME=$S/home bp3 init            # in a fixture repo
completion: installed at $S/share/bp3/completions/_bp3 (make install delivers it)
$ find $S/home -newer <stamp>      # nothing
```

```yaml
objective: one command installs the build at HEAD, and no repo command writes outside its repo
prove by:
  - test/install.sh: clean install into a scratch PREFIX (bp3-q --build == BUILD == scripts/build-id;
    wrapper and skills identical to the source; SOURCE names the main checkout and HEAD, also when run from a desk);
    refusal on a tracked change with PREFIX untouched (find -newer);
    reinstall prints was -> now; BP3_COMPLETIONS_DIR in scratch receives _bp3 from make install
  - test/skills.sh (or install.sh): HOME and ZDOTDIR in scratch with a completions dir present; bp3 init writes nothing there
  - make release still refuses without the tag (release-check unchanged)
  - make check-full
done when: each case holds, and the install and init cases fail on master
```

## Diagram

```text
make install ──► tracked changes? ──yes──► refuse, exit 1, write nothing
                      │ no
                      ▼
           dune build main.exe (Build_info from build.1)
                      ▼
        install-bp3.sh <_build/…/main.exe>   (the artifact path it already takes)
           ├─► $PREFIX/bin/bp3-q, bin/bp3, share/bp3/{skills,scripts,completions}
           ├─► $PREFIX/share/bp3/BUILD  ← bp3-q --build
           ├─► $PREFIX/share/bp3/SOURCE ← {main checkout, HEAD}
           └─► zsh completion → BP3_COMPLETIONS_DIR or the first existing completions dir
bp3 init / skills install ──► renders inside the repo only; prints the completion's path
```

## Pseudocode

```python
def make_install(prefix):
    if git_rc("diff", "--quiet", "HEAD", "--") != 0:
        die("install: the tree has tracked changes; commit first")
    dune_build("src/quest/main.exe")
    old = run(prefix / "bin/bp3-q", "--build") or "none"   # an old engine has no --build: "unknown"
    install_bp3(artifact="_build/default/src/quest/main.exe", prefix=prefix)
    build = run(prefix / "bin/bp3-q", "--build")
    write(prefix / "share/bp3/BUILD", build + "\n")
    main = dirname(git("rev-parse", "--path-format=absolute", "--git-common-dir"))   # the main checkout, even from a desk
    write(prefix / "share/bp3/SOURCE", json({"repo": main, "commit": git("rev-parse", "HEAD")}))
    deliver_zsh_completion(prefix / "share/bp3/completions/_bp3", env.get("BP3_COMPLETIONS_DIR"))
    print(f"installed bp3 {build} -> {prefix} (was: {old})")
```

## Tables

| Field | Value |
|---|---|
| Intent | reinstalling is one command, and only that command touches the machine |
| Lane | standard |
| Output | `Makefile` (`install`), `scripts/install-bp3.sh` (BUILD, completion delivery, was→now), `bin/bp3` (`skills_install` stops writing completions), `test/install.sh`, `test/skills.sh` |
| Acceptance | the trace above; fails today (no artifact; init writes the completion) |
| Depends on | build.1 |

| Command | Writes outside the repo |
|---|---|
| `make install` | `$PREFIX/…`, the zsh completions dir |
| `make release` | `dist/` in the bp3 repo only (unchanged) |
| `bp3 init`, `bp3 skills install` | nothing (today: the zsh completion) |

## Prose

Reinstalling today means either cutting a tagged release, which nobody
has done since 2026-11-14, or knowing that `install-bp3.sh` takes an
artifact path and handing it `_build/…/main.exe`. That friction is why
the install is a week stale. `make install` takes the second road on
purpose: the script already copies all three pieces at once and refuses
nothing about a hand-built artifact, so the change is a Makefile recipe,
a clean-tree check, the BUILD file and the completion move.

Only clean trees install, so the installed build id never ends in
`-dirty` and always names a commit someone can check out ("only clean
commits move").

The completion moves because `init` runs per repo, and per desk if a
session runs it there. Each run rewrote a shared file
(`/opt/homebrew/share/zsh/site-functions/_bp3` on this machine) from
whatever share was installed. One machine-wide file belongs to the
one machine-wide command. `BP3_COMPLETIONS_DIR` keeps working, read by
install now.

Edge: an engine installed before build.1 has no `--build`; its `bp3-q
--build` answers `E_USAGE`, which the recipe reads as `unknown` in the
"was" line.

## Tests

Known cases: clean install, dirty refusal with PREFIX untouched,
reinstall was→now, completion into `BP3_COMPLETIONS_DIR`, `init` writing
nothing outside the repo, `make release` still tag-gated.
Property-based: omitted. These are filesystem effects of four commands;
the cases enumerate them.
