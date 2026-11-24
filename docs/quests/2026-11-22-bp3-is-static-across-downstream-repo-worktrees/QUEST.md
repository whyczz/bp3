---
status: proposed
home_repo: bp3
date: 2026-11-22
bump: minor
---

# bp3-is-static-across-downstream-repo-worktrees: one installed bp3, known build, known latest, desks that build

TL;DR
One installed bp3 serves every downstream repo and every desk in it,
and you can always tell which build it is and whether a newer one
exists. The engine prints its build (`bp3-q --build` → `0.2.0+e79a73a`),
`make install` installs HEAD's build in one command with no tag, and the
version finally moves: every quest declares `bump:` at framing, and
promotion bumps, tags, releases and installs (this quest takes bp3 to
0.3.0). An installed bp3 older than the latest tag says so with
`W_INSTALL_BEHIND`, in every verdict and at session start in every repo
that calls it. `bp3 skills check` refuses stale renders and a mixed
install. Host repos get desks. The one decision: a **host desk lives
outside the repo tree** (`../<repo>.desks/<run_id>`), because tools that
find their project root by walking up (dune, and predictor's pre-commit
through it) build the outer checkout when the desk is nested inside it.
bp3's own (self) desks stay at `.bp3/worktrees/`.

ELI5
bp3 is one program installed once on the machine. Other repos, like
predictor, just call it. Today nobody can tell how old that installed
copy is (somewhere between 64 and 112 commits behind), its version number
hasn't changed in 263 commits, reinstalling takes a release dance, and
the copies of its instructions inside predictor go stale silently. After
this quest the program says which code it was built from, every
finished quest raises the version, any repo using an older copy gets
told so in every answer, and reinstalling is one command. Predictor also
gets the same "separate desk per quest" bp3 uses for itself, placed
beside the repo instead of inside it, so predictor's build tools don't
get confused.

## Context

Owner, 2026-11-22, after promoting induct-inline-as-default: "how do we
use worktrees for predictor? ~/m/predictor. we'd need to rebuild opam,
etc for bp3. how'd we reinstall bp3, and how can we make bp3 available
throughout different worktrees, from a downstream repo like predictor or
esc3, then the bp3 cli should be static no?", then "can be a new /quest,
start with the /red-chair -> apply fixes, then write the
bp3-is-static-across-downstream-repo-worktrees quest". On the draft: "we
need a version system no>?", "and we need a check to see the latest
version?", "yep, add it to this quest", "and check it out with
predictor", "how are we propagating the W_INSTALL_BEHIND?", "should
we fetch checkout from github if local bp3 is not there?", then "good
call -> let's just have the local bp3 check -> with a BP3_HOME env var
or BP3_REPO_HOME".

Ground, read or run this session:

| Fact | Source |
|---|---|
| `bp3` on PATH is `~/.local/bin/bp3` (the bash wrapper), installed 2026-11-20 16:26; `~/.local/bin/bp3-q` is a Mach-O arm64 binary linked only against `/usr/lib/libSystem.B.dylib` | `which -a bp3`, `file`, `otool -L` |
| the installed wrapper equals `bin/bp3` from `707cbf5` (2026-11-18) up to the next change (`7bbd117`, 2026-11-22); master was at `aad8949` when it was installed: the install is 64–112 commits behind master, and nothing records which commit it is | `cmp` against `git show <c>:bin/bp3`, `git rev-list` |
| `bp3-q --version` prints `0.2.0`; the source says `bp3_version = "0.2.0"`; the only tag, `v0.2.0`, is at `fcfce07` (2026-11-14), 263 commits behind master | `src/quest/gitx.ml:3`, `git tag` |
| the version system exists on paper: semver, a bump-meaning table (MAJOR = ledger meaning changes, MINOR = compatible addition, PATCH = none), annotated tag `v<version>`, `release-check`; it never says when to bump | `docs/quests/2026-11-14-bp3-cli-small-fixes/nodes/node-5-release-pattern/NODE.md` |
| the table has no CLI row; the `bp3 g` → `bp3 q` door rename (`6222334`, 2026-11-18) broke the CLI after `v0.2.0` | `git log v0.2.0..master` |
| the version guard compares the version in this repo's ledgers with the binary's: older MAJOR refuses writes (`E_VERSION_AHEAD`), older MINOR/PATCH warns (`W_VERSION_AHEAD`); it can't say a newer bp3 exists elsewhere | `src/quest/store.ml:351-385`, `src/quest/main.ml:630-640` |
| in `~/m/predictor`, `bp3 q r 2026-11-22-predictor-conventions-naming` answers `warnings: []`: nothing tells predictor its bp3 is behind | observed |
| predictor's `.claude/skills/induct-inline/SKILL.md` still says "one node in flight" (2 hits): its renders come from the 2026-11-20 share | `grep -c` |
| the installed wrapper's `CORE_SKILLS` lacks `induct-inline-yolo` | `diff bin/bp3 ~/.local/bin/bp3` |
| `make install` runs `scripts/install-bp3.sh`, which wants `dist/bp3-q-v<version>-<os>-<arch>` from `make release`; `make release` runs `scripts/release-check`, which refuses unless annotated tag `v<version>` points at HEAD; there is no `dist/` | `Makefile:52-65`, `scripts/install-bp3.sh`, `scripts/release-check` |
| `install-bp3.sh` takes an artifact path as `$1`: a hand-built `main.exe` installs with no tag and no checksum | `scripts/install-bp3.sh:16-27` |
| tests pin the literal version: `test/release.sh:41` (`--version` = `0.2.0`), `test/g.sh:71` (a fresh ledger line's `bp3_version` = `0.2.0`) | `grep -rn 0.2.0 test/` |
| in host mode the wrapper's `root` is `~/.local`, `q_bin` (`$root/_build/…/main.exe`) is absent, so it runs `bp3-q` with `BP3_ROOT=$(target_root)`, the caller's repo | `bin/bp3:10, 327-337` |
| `bp3 skills check` compares only workflow renders (`$WORKFLOW_NAMES`), never SKILL.md renders | `bin/bp3`, `skills_check` |
| `bp3 init` / `bp3 skills install` copy `_bp3` into the first existing of `~/.zsh/completions`, `/opt/homebrew/share/zsh/site-functions`, …, unless `BP3_COMPLETIONS_DIR` is set | `bin/bp3:259-282` |
| `bp3 q hooks` writes ledger events and prints nothing to stdout; predictor's `.claude/settings.json` runs it on SessionStart, PreToolUse, PostToolUse and more | `src/quest/hooks.ml`, predictor `.claude/settings.json` |
| quest state is git refs under `refs/heads/bp3/`, written with `hash-object`/`commit-tree`/`update-ref`; refs are shared by every worktree of a repo | `src/quest/gitx.ml:217-246`, `src/quest/store.ml:320` |
| predictor has 11 `refs/heads/bp3/*` refs and no `.bp3/` dir: its quests ran in the shared tree, never a desk | `git for-each-ref`, `ls` |
| the skills say host mode has no desk (`induct` step 2.5 "self mode only"; induct-inline step 1 "host mode works in the repo"); `harness desk prepare` itself has no mode check, it runs `git worktree add` | `skills/induct/SKILL.md:76,91`, `skills/induct-inline/SKILL.md:35`, `src/quest/worktree.ml:120-136, 279` |
| `harness desk prepare` already takes `--path` | `src/quest/worktree.ml:294, 500` |
| predictor builds with dune package management: `dune.lock/` (59 tracked files, 58 packages incl. the OCaml 5.5.2 compiler); `_opam/` (702M, gitignored) carries the editor's `dune`, ocaml-lsp-server and ocamlformat 0.29.0; agents' `dune` is `~/.opam/default/bin/dune` 3.25.0 | predictor `dune-project`, `README.md:262-287`, `which dune` |
| opam picks predictor's `_opam` from any subdir (`opam switch show` in `predictor/docs` → `/Users/whycz/m/predictor`) | observed |
| predictor's `.githooks/pre-commit` cds to `git rev-parse --show-toplevel`, prefers `$root/_opam/bin`, runs `dune build @fmt` | predictor `.githooks/pre-commit` |
| dune takes `--root=DIR` (or `DUNE_ROOT`); bp3's own Makefile adds `--root=.` when `$(CURDIR)` contains `/.bp3/worktrees/` | `dune build --help`, `Makefile:7-8` |
| `GRADING.md` absent → the brief says "No GRADING.md at <sha7>: run the repo's documented test gate and name it."; predictor has none | `src/quest/brief.ml:91-93`, `git ls-files` |
| the wrapper merges hooks into `.claude/settings.json` with jq, keeping other keys | `bin/bp3:232-245` |
| `~/m/esc3` does not exist | `ls` |

Scratch-clone experiment (predictor cloned to the scratchpad with its
`bp3/*` refs, installed bp3, nothing in `~/m/predictor` touched):

```text
$ bp3 config | jq -r .mode                                   host
$ bp3 q r 2026-11-22-predictor-conventions-naming            {"fin":"goal_fin","n":10}
$ bp3 harness desk prepare --quest 2026-11-22-predictor-conventions-naming
  {"ok":true,...,"path":".bp3/worktrees/2026-11-22-predictor-conventions-naming",...}
$ cd <desk> && bp3 q r ...                                   {"fin":"goal_fin","n":10}   (same state)
$ cd <desk> && dune build
  Entering directory '<clone root>'
  Error: No rule found for alias .bp3/worktrees/2026-11-22-predictor-conventions-naming/default
$ cd <desk> && dune build --root .                           138 s cold, 0 s warm, _build 491M
$ cd <desk> && dune test --root .                            ok (demo_ws, demo_orders checks)
```

Related, not promoted: `docs/icebox/2026-11-15-bp3-portable-mvp-dogfood-esc3.md`
(bp3 driving a repo it did not grow up in). Its "nothing is installed"
and "skills have no road" blockers were settled by dogfood.3; its esc3
repo still doesn't exist. This quest is repo-generic and proves on
predictor; it takes none of that entry's decisions.

## Terms

| Term | Meaning |
|---|---|
| downstream repo | a repo where bp3 runs in host mode (`repo_mode` = `host`): predictor today |
| the install | what `scripts/install-bp3.sh` writes under `$PREFIX`: `bin/bp3` (the wrapper), `bin/bp3-q` (the engine), `share/bp3/` (skills, scripts, completions, `BUILD`, `SOURCE`) |
| version | `bp3_version` in `src/quest/gitx.ml`, semver; the compatibility promise. Moves only at promotion |
| build id | `<bp3_version>+<sha7>`, plus `-dirty` when built from a tree with tracked changes, or `<bp3_version>+unknown` outside git; printed by `scripts/build-id`. Names the exact commit, releases and dev installs alike |
| `Build_info.build` | the build id compiled into the engine by a dune rule that runs `scripts/build-id` |
| `bp3-q --build` | prints `Build_info.build`; `--version` is unchanged and still prints `bp3_version` |
| `bump:` | QUEST.md frontmatter field, `major | minor | patch | none`, decided at framing against `RELEASING.md`'s table; `make lint` refuses a proposed or active quest without it |
| `RELEASING.md` | new root doc: what each bump means (node-5's table plus a CLI row), bump at promotion, the promotion steps |
| `scripts/bump <level>` | edits `bp3_version`, commits `chore(release): v<new>`, and tags `v<new>` (annotated) at that commit; refuses a tree with tracked changes; never pushes |
| `make install` | builds `main.exe` at HEAD and installs every piece plus the zsh completion from a clean tree; no tag, no `dist/` |
| `share/bp3/BUILD` | one line, the build id of the install that wrote the share |
| `share/bp3/SOURCE` | JSON `{"repo","commit"}`: the bp3 main checkout the install was built from (the common dir's checkout, never a desk) and the full commit |
| `BP3_REPO_HOME` | env var: an absolute path to a local bp3 checkout; when set and non-empty, `Install.status` reads its tags instead of `SOURCE`'s repo. Not `BP3_HOME`: `*_HOME` conventionally names an install dir (`JAVA_HOME`), which for bp3 is `PREFIX` |
| the source checkout | the local bp3 checkout `Install.status` reads: `$BP3_REPO_HOME`, else `SOURCE`'s repo. Never the network |
| `Install.status` | the one function in `bp3-q` that answers "how old am I": `{version, build, source, source_from, latest_tag, behind_master, unchecked}`, from `share/bp3/` beside the running executable and the source checkout's tags; `unchecked` names why no checkout could be read; `null` outside the installed layout |
| `W_INSTALL_BEHIND` | warning: the installed version is older than the source checkout's latest `v*` tag. Facts `{installed, latest_tag}`. Never blocks |
| render drift | a repo's skill render differs from what `bp3 skills install` would write now from the installed share |
| `E_INSTALL_MIXED` | `bp3 skills check` refusal: `bp3-q --build` ≠ `share/bp3/BUILD` (installed layout only) |
| host desk | a desk prepared in a host repo; its default path is `../<repo>.desks/<run_id>`, beside the repo, never inside it |
| `E_DESK_NOT_IGNORED` | `harness desk prepare` refusal: the desk registry dir `.bp3/` is not gitignored, so the root checkout would turn dirty |

## Inputs

| Input | Source |
|---|---|
| git HEAD and tracked-tree state of the bp3 checkout | read by `scripts/build-id` at build time |
| `bump:` in QUEST.md | read by `make lint` (presence) and at promotion (the level passed to `scripts/bump`) |
| `PREFIX` | `make install`, default `$HOME/.local` (as today) |
| `BP3_COMPLETIONS_DIR` | `make install` only, overriding the completions-dir search; `bp3 init` stops reading it |
| `share/bp3/BUILD`, `share/bp3/SOURCE`, and the source checkout's `refs/tags/v*` | read by `Install.status` |
| `BP3_REPO_HOME` | read by `Install.status` in the installed layout only; wins over `SOURCE`'s repo; empty counts as unset; relative is refused as `unchecked` |
| a downstream repo's renders (`.claude/skills`, `.pi/skills`, `.agents/skills`, workflows) | read by `bp3 skills check` |
| `--path <dir>` | `harness desk prepare`, as today; still wins over the default path |

## Outputs

| Output | Shape |
|---|---|
| `bp3-q --build` | one line, the build id |
| `bp3 config` | gains `"build"` and `"install": {version, build, source, source_from, latest_tag, behind_master, unchecked}` (`null` outside the installed layout) |
| every `bp3 q`/`n`/`e` verdict | `warnings` gains `W_INSTALL_BEHIND` when it applies, beside `W_VERSION_AHEAD` |
| `bp3 q hooks` on SessionStart | one stdout line when behind: `bp3 0.2.0+aad8949 is installed; v0.3.0 is tagged in /Users/whycz/m/bp3: run make install there`; or, with no checkout to read: `bp3 0.2.0+aad8949 is installed; can't check for a newer one: /Users/whycz/m/bp3 is not a git checkout (set BP3_REPO_HOME to your bp3 checkout)` |
| `make install` | prints `installed bp3 <build> -> <prefix> (was: <old build or unknown or none>)`; refuses a tree with tracked changes, writing nothing; writes `BUILD` and `SOURCE` |
| `scripts/bump <level>` | `{"old","new","tag","commit"}`; a release commit and an annotated tag, no push |
| `make lint` | refuses a proposed or active QUEST.md with no legal `bump:` |
| `RELEASING.md` | new root doc |
| `bp3 skills check` | `E_RENDER_STALE` now also names stale SKILL.md renders; new `E_INSTALL_MIXED {binary, share}`; its ok JSON carries `warnings` |
| `bp3 init`, `bp3 skills install` | write nothing outside the repo; print where the installed completion lives |
| `harness desk prepare` in host mode | default path `../<repo>.desks/<run_id>`; `E_DESK_NOT_IGNORED {path: ".bp3/"}` when the registry is not ignored |
| `.claude/settings.json` (host render) | gains `permissions.additionalDirectories: ["../<repo>.desks"]`, merged like the hooks |
| skills | induct, induct-inline, using-bp3: desks in both modes; quest: `bump:` in the file shape; promotion follows `RELEASING.md`; reports quote `W_INSTALL_BEHIND` and `W_VERSION_AHEAD` |

## Acceptance gates (observed today, then design trace)

Observed 2026-11-22:

```text
$ ./_build/default/src/quest/main.exe --build
{"ok":false,"error":{"code":"E_USAGE",...}}
$ make install          # -> install-bp3.sh: no artifact dist/bp3-q-v0.2.0-darwin-arm64; run make release first
$ ./scripts/release-check   # tag v0.2.0 at fcfce07…, HEAD is e79a73a…
$ git tag -l 'v*'           # v0.2.0, 263 commits ago
$ (in ~/m/predictor) bp3 q r 2026-11-22-predictor-conventions-naming | jq -c .warnings
[]
$ grep -c 'one node in flight' ~/m/predictor/.claude/skills/induct-inline/SKILL.md
2
$ (scratch predictor clone) cd <nested desk> && dune build
  Entering directory '<clone root>' … No rule found for alias .bp3/worktrees/…/default
```

Design trace, after the quest:

```text
build.1    bp3-q --build -> 0.2.0+<sha7>; edit a tracked file, rebuild -> 0.2.0+<sha7>-dirty;
           bp3 config | jq -r .build -> the same; bp3-q --version -> 0.2.0
version.1  scratch clone: scripts/bump minor -> gitx.ml 0.3.0, HEAD "chore(release): v0.3.0", annotated v0.3.0 at HEAD,
           scripts/release-check -> 0.3.0; a proposed QUEST.md without bump: -> make lint names it;
           test/release.sh and test/g.sh read the constant, so they pass at 0.3.0
install.1  make install PREFIX=$S -> $S/bin/bp3-q --build == scripts/build-id == $(cat $S/share/bp3/BUILD);
           $S/share/bp3/SOURCE names the main checkout; tracked change -> refused, $S untouched;
           HOME=$S/home bp3 init in a fixture repo -> nothing new under $S/home
install.2  fixture host repo, one SKILL.md render edited -> bp3 skills check -> E_RENDER_STALE naming it;
           $S/share/bp3/BUILD rewritten -> E_INSTALL_MIXED {binary, share}
install.3  $S installed from a scratch bp3 clone at 0.2.0, then v0.3.0 tagged there ->
           (fixture host repo) bp3 q r q | jq .warnings -> ["W_INSTALL_BEHIND"]; bp3 config .install.latest_tag -> v0.3.0;
           SessionStart payload | bp3 q hooks -> one line naming both; PreToolUse -> no output;
           reinstall at the tag -> no warning; BP3_REPO_HOME=<a clone tagged past it> -> W_INSTALL_BEHIND, source_from BP3_REPO_HOME;
           SOURCE repo gone -> no warning, install.unchecked names it, SessionStart prints the can't-check line
desk.1     fixture host repo with dune-project -> bp3 harness desk prepare --quest q -> ../<repo>.desks/quest-q;
           an upward root search from the desk stops at the desk; root git status empty;
           .bp3/ not ignored -> E_DESK_NOT_IGNORED, no worktree; bp3 repo (self) -> .bp3/worktrees/... unchanged
skills.1   induct, induct-inline, using-bp3, quest (source and renders): host mode prepares a desk, "has no desk" gone;
           quest file shape carries bump:; promotion follows RELEASING.md; reports quote W_INSTALL_BEHIND
dogfood.1  owner: make install from the quest desk; ~/m/predictor: bp3 skills check stale -> skills install -> ok;
           BP3_REPO_HOME=<scratch clone tagged v0.3.0> -> predictor's bp3 q r carries W_INSTALL_BEHIND, the SessionStart line prints;
           a host desk at ~/m/predictor.desks/…; dune build there builds the desk; one node to node_fin
           through /induct-inline in that desk; ~/m/predictor git status empty throughout
all        make check-full rc 0
promotion  merge -> scripts/bump minor -> v0.3.0 -> make release -> push on the owner's word;
           predictor sessions see W_INSTALL_BEHIND until make install at v0.3.0, then none
```

## Goal and why

Make the installed bp3 the one engine every downstream repo and desk
calls, with a build you can name, a version that means something, a
warning when a newer one is out, a reinstall you can do in one command,
and drift you can see. Why: predictor already runs bp3 quests against an
engine and skills days stale with nothing saying so, and it can't use
desks at all, so its quests share one working tree. The induct-inline
default just promoted assumes a quest desk plus grade desks; downstream
repos can't follow it today.

## Success picture

- After promotion, `~/.local/bin/bp3-q --version` prints `0.3.0`, and
  `--build` names the `v0.3.0` commit, after one `make install`.
- Between that tag and the reinstall, a session in `~/m/predictor` sees
  `W_INSTALL_BEHIND` in its first context line and in every bp3 verdict;
  after the reinstall it sees none.
- In `~/m/predictor`, `bp3 skills check` is ok, and a quest runs inline
  in `~/m/predictor.desks/<run>` with grade desks beside it, its
  `dune build` building the desk, its root checkout clean the whole time.
- The dogfood's friction list is written in its NODE.md build notes.

## Scope

| In | Out |
|---|---|
| a build id in the engine, `bp3 config`, and the share | a ledger stamp of the build (Open question 3) |
| `bump:` per quest, `RELEASING.md`, `scripts/bump`, the first bump (0.3.0) at this quest's promotion | 1.0 (Open question 7); changing `make release` / `publish` (the tagged path stays) |
| `W_INSTALL_BEHIND` from the local source checkout: verdicts, SessionStart, `config`, `skills check`, reports | any network check (settled local only: Open question 6); auto-reinstall; update prompts |
| `make install` from a clean HEAD, no tag | a package manager |
| the zsh completion moves from `init` to `install` | bash completion delivery (still printed, never written) |
| `skills check` covers SKILL.md renders and install mixing | |
| host desks beside the repo; the `.bp3/` ignore check; `additionalDirectories` in the Claude render | moving self desks out of `.bp3/worktrees/` (Open question 1); pi and Muse sandbox settings |
| skill text: desks in both modes, `bump:`, promotion steps, quoting the warnings | |
| one predictor dogfood node | predictor's own fixes (GRADING.md, pre-commit `_opam` lookup): listed as friction, committed in predictor on the owner's word |
| | Linux builds, a fully static Linux binary |

## Constraints at approval

- Constraints pass: `scripts/build-id` and `scripts/bump` are bash
  running `git` and `sed` (both in bash `libs`); the dune rule is a
  `dune` file (ocaml `files`); `Install.status` runs `git` from OCaml as
  `Gitx` already does; `SOURCE` is JSON (data); jq for the settings merge
  is already in bash `libs`. No new language, library or surface:
  `--build`, `W_INSTALL_BEHIND`, `E_INSTALL_MIXED`, `E_DESK_NOT_IGNORED`
  extend the existing CLI; `BP3_REPO_HOME` joins the existing `BP3_*`
  env vars. No network call is added (Open question 6, settled).
- Common-sense pass (`CONTEXT.md:39`): a git worktree per agent or task
  is the mainstream isolation (Claude Code sub-agents, worktrunk, Gas
  Town, checked 2026-11-19); bp3 calls them desks. Where those tools put
  the worktree (in-tree vs beside the repo) was not re-checked this
  session; Open question 1 re-checks it before red-ink.

## Human touchpoints

- Approve this frame (red-ink first, if wanted).
- dogfood.1: run or OK `make install` into `~/.local` from the quest desk
  (it changes the installation), name the predictor quest and node to
  run, and OK the predictor commits it needs.
- Promotion (`goal_fin`): the merge, `scripts/bump minor` (v0.3.0),
  `make release`, `make install`, and the push of master and the tag.

## Nodes

### Milestone: build

| Node | TL;DR |
|---|---|
| [build.1 - build-id](nodes/node-build-1-build-id/NODE.md) | the engine knows its commit: `bp3-q --build`, `bp3 config .build`, from `scripts/build-id` via a dune rule |

### Milestone: version

> **Superseded (2026-11-23):** `version.1` (`bump:`, `RELEASING.md`, `scripts/check-bump`, `scripts/bump`) is superseded by [2026-11-23-quest-promote-release](../2026-11-23-quest-promote-release/QUEST.md), which ships top-level `bp3 release`, `scripts/check-bump`, `RELEASING.md`, and unpinned version tests.

| Node | TL;DR |
|---|---|
| [version.1 - bump-at-promotion](nodes/node-version-1-bump-at-promotion/NODE.md) | `bump:` in every quest, `RELEASING.md` (node-5's table plus a CLI row), `scripts/bump` commits and tags; tests stop pinning `0.2.0` |

### Milestone: install

| Node | TL;DR |
|---|---|
| [install.1 - make-install](nodes/node-install-1-make-install/NODE.md) | `make install` installs HEAD's build in one command with no tag, writes `share/bp3/BUILD` and `SOURCE`, and is the only bp3 command that writes outside a repo (the zsh completion moves here from `init`) |
| [install.2 - drift-check](nodes/node-install-2-drift-check/NODE.md) | `bp3 skills check` refuses stale SKILL.md renders and a mixed install (`E_INSTALL_MIXED`) |
| [install.3 - latest-check](nodes/node-install-3-latest-check/NODE.md) | `Install.status` and `W_INSTALL_BEHIND`, carried in every verdict, at SessionStart, in `config` and `skills check` |

### Milestone: desk

| Node | TL;DR |
|---|---|
| [desk.1 - host-desk-path](nodes/node-desk-1-host-desk-path/NODE.md) | host desks default to `../<repo>.desks/<run_id>`; `E_DESK_NOT_IGNORED`; the Claude render lists the desks dir in `permissions.additionalDirectories` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - downstream-skills](nodes/node-skills-1-downstream-skills/NODE.md) | skill node: desks in both modes, `bump:` in the quest file shape, promotion per `RELEASING.md`, reports quote the version warnings |

### Milestone: dogfood

| Node | TL;DR |
|---|---|
| [dogfood.1 - predictor-desk](nodes/node-dogfood-1-predictor-desk/NODE.md) | reinstall, refresh predictor's renders, see `W_INSTALL_BEHIND` in predictor, run one predictor node inline in a host desk; write the friction list |

## Scorecard

| Field | Target |
|---|---|
| nodes at `node_fin` | 8 of 8 |
| installed build after `make install` | equals `scripts/build-id` in the checkout it ran in |
| `bp3-q --version` after promotion | `0.3.0` |
| `W_INSTALL_BEHIND` in predictor | present while behind the tag, absent after the reinstall |
| added time per `bp3 q` call from `Install.status` | measured (one `git for-each-ref` on the source checkout) |
| predictor desk cold `dune build` | recorded (138 s in the scratch clone); warm 0 s |
| predictor root `git status --short` during dogfood | empty at every check |
| rounds per node, author and grade wall | from `bp3 q <quest> metrics r` |

## Risks and red chair

Red chair, engineering lens, 2026-11-22, on the ground above (the
installed bp3 as downstream repos use it, and the owner's plan to give
predictor worktrees). Findings, severity order; each names where this
frame settled it.

1. **[major] The install is stale and nothing can tell.** Its wrapper
   matches `bin/bp3` from 2026-11-18; it is 64–112 commits behind master
   and records no commit. The wrapper lacks `induct-inline-yolo`;
   predictor runs the old induct-inline. Settled: build.1 (build id),
   install.1 (`BUILD`, `SOURCE`), install.2 (drift check).
2. **[major] The version never moves, so every version check is blind.**
   `0.2.0` for 263 commits, a CLI break among them. node-5 defined what a
   bump means but not when; the guard compares numbers that never change,
   and predictor's verdicts carry no warning. Settled: version.1 (bump at
   promotion, declared per quest), install.3 (`W_INSTALL_BEHIND`).
3. **[major] A nested desk breaks root-guessing tools.** `dune build` in
   a desk under the repo built the outer checkout's root and refused the
   desk's alias (experiment above); predictor's pre-commit runs the same
   `dune build @fmt` from the desk's toplevel. bp3 survives only through
   its own Makefile's `--root=.` rule. Settled: desk.1 puts host desks
   beside the repo, which fixes every upward-searching tool at once
   instead of pinning each one.
4. **[major] Reinstall has no one-command path.** `make install` needs a
   `make release` artifact, which needs an annotated tag at HEAD; there
   is no `dist/`. The 2026-11-20 install must have passed an artifact by
   hand (inference: the only path the script allows). Settled: install.1.
5. **[major] Render drift is invisible.** `skills check` compares only
   workflow renders; predictor's stale SKILL.md renders pass. Settled:
   install.2.
6. **[major] `bp3 init` writes a global file from a repo command.** Every
   `init` in every repo or worktree rewrites the zsh completion in a
   shared dir (`/opt/homebrew/share/zsh/site-functions` here), from
   whatever share is installed. Settled: install.1 moves it to `make
   install`, the one command whose job is the machine.
7. **[major] Host desks are banned by skill text, not code.** The skills
   say "self mode only"; `harness desk prepare` worked in a host clone and
   both checkouts read the same state. Settled: skills.1.
8. **[minor] A warning nobody reads is no propagation.** A field in
   `bp3 config` alone would be read by no one. Settled: install.3 puts
   `W_INSTALL_BEHIND` where sessions already look (every verdict's
   `warnings`, the SessionStart context line) and skills.1 makes
   conductors quote it in their reports, so it reaches the owner.
9. **[minor] A desk has no `_opam`.** Predictor's pre-commit looks for
   `$root/_opam/bin` with root = the desk, so it falls back to the
   default switch, whose ocamlformat version was not checked. Deliberately
   open: dogfood.1 records it; the fix is predictor's (find `_opam` via
   `git rev-parse --git-common-dir`).
10. **[minor] Downstream briefs have no gate file.** Predictor has no
    `GRADING.md`; the brief then tells the grader to find the repo's
    gate. Deliberately open: dogfood.1 adds predictor's; Open question 4.
11. **[minor] "Static".** `bp3-q` links only `libSystem` — as static as
    macOS allows. Linux not checked. Out of scope.

What it survived: **state across worktrees.** Quest state is refs under
`refs/heads/bp3/`, shared by every worktree; the desk and the root read
the same rollup. And **"rebuild opam for bp3"**: host mode never builds
bp3. The per-desk cost is the downstream repo's own `_build` (138 s cold
for predictor, from `dune.lock`), not opam.

Red chair on the source (the owner's prompts):

- "the bp3 cli should be static no?" — it already is; what's missing is
  its identity. Changed: the quest is about the build id, versions,
  one-command install and drift, not about linking.
- "we'd need to rebuild opam, etc for bp3" — not in host mode (above).
  Changed: no node touches opam; dogfood.1 measures the real per-desk cost.
- "we need a version system no?" — it exists (node-5) and was never
  used. Changed: version.1 adds only the missing rule (when) and the tool
  (`scripts/bump`); the meaning table is reused, plus one CLI row.
- "a check to see the latest version" — the boring version is a field in
  `bp3 config`. Changed: install.3 also carries it in every verdict and
  at session start, because that is where a downstream session looks.
  It reads a local checkout's tags only; "should we fetch checkout from
  github if local bp3 is not there?" was answered no by the owner.
  Changed: `BP3_REPO_HOME` names the checkout when `SOURCE` can't, and a
  missing checkout prints a can't-check line instead of staying silent.

Opening attack this frame withstood: "put the desk inside the repo and
pin `--root .` everywhere, like bp3's Makefile." That works per tool and
per repo, and predictor has no Makefile; every new downstream repo would
re-learn it. Beside-the-repo costs one Claude Code setting (desk.1) and
loses opam's `_opam` lookup (finding 9).

## Open questions

1. Desk placement (owner, red-ink): `../<repo>.desks/<run_id>` beside
   the repo (this frame) or a home dir such as `~/.bp3/desks/<repo>/`;
   and whether self desks follow later. Re-check where Claude Code
   worktrees and worktrunk put theirs first.
2. Does `permissions.additionalDirectories` let a Claude Code session
   rooted in the repo edit `../<repo>.desks/…` without a prompt? desk.1
   renders it; dogfood.1 is the live probe.
3. Stamp `bp3_build` on ledger lines too, so a ledger says which engine
   wrote each line? Evidence only; deferred unless dogfood.1 needs it.
4. Should `bp3 init-repo` scaffold a `GRADING.md` stub in host repos?
5. Does dune's shared cache cover dune-pkg builds, so a second desk's
   cold build is shorter than the first? dogfood.1 times two desks.
6. Settled (owner, 2026-11-22): no GitHub check. "let's just have the
   local bp3 check -> with a BP3_HOME env var or BP3_REPO_HOME". A
   machine with no checkout sets `BP3_REPO_HOME` or sees the can't-check
   line (install.3).
7. When does bp3 go 1.0 (owner)? Until then a CLI break rides a minor,
   as `RELEASING.md` will say.

## Node diagram

```text
build.1 ─┬─► install.1 ──► install.2 ──► install.3 ─┬─► skills.1 ──► dogfood.1
         └─► version.1 ─────────────────────────────┤
desk.1 ─────────────────────────────────────────────┘

cohort 1: build.1, desk.1                (independent)
cohort 2: version.1, install.1
cohort 3: install.2
cohort 4: install.3
cohort 5: skills.1                       (desk.1, version.1, install.3)
cohort 6: dogfood.1                      (skills.1, install.3; owner: reinstall, pick the predictor node)
promotion: merge, bump minor -> v0.3.0, release, install, push (owner)
```
