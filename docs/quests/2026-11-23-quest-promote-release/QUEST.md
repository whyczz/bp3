---
status: active
home_repo: bp3
date: 2026-11-23
bump: minor
---

# quest-promote-release: atomic CAS `bp3 release` (quest & commit) + tag-gated local auto-sync

TL;DR
Ship a top-level, owner-gated **`bp3 release`** CLI door (`CONSTRAINTS.md` surface, owner-signed 2026-11-23) with two modes: **`bp3 release <quest>`** (promotes a `goal_fin` quest using `QUEST.md`'s `bump: major | minor | patch | none`, enforced forward-only by `scripts/check-bump` in `make lint`) and **`bp3 release --commit <sha>`** (cuts a lightweight bugfix release from a commit hash without a quest, defaulting to `--bump patch`). Both modes share one pure OCaml engine (`src/quest/release.ml`) and one atomic git CAS transaction (`git update-ref --stdin` over `refs/heads/<target>` + annotated `refs/tags/vX.Y.Z`), reading the repo's latest `vX.Y.Z` tag at release time (forward-only, zero retroactive tagging; baseline `0.0.0` if untagged) so parallel quests and hotfixes never collide on pre-assigned versions. A deterministic **"What changed"** summary is written verbatim to the annotated tag message and—when a GitHub remote exists and `--no-gh` is absent—published as a **GitHub Release** (`git push` non-force + publish-once `gh release create`, with `--publish-only` recovery). Finally, **tag-gated local auto-update** keeps downstream host repos (like `~/m/predictor`) fresh strictly on released tags (never on untagged commits): `bp3 release` in `bp3` self mode builds and installs the tagged release to `$PREFIX` (`~/.local`, stamping `share/bp3/RELEASE`), and `bp3 q hooks` on `SessionStart` in clean host repos automatically runs `bp3 skills install --harness=all` and commits `chore(bp3): sync skills/hooks to v<tag>` (or warns `W_BP3_UPDATE_AVAILABLE` without touching git when dirty).

ELI5
Today `bp3` has sat at `v0.2.0` for 263+ commits, `~/m/predictor`'s skills are days out of date (missing `/warden` and `induct-inline-yolo`), and there is no safe way to promote parallel quests or cut a quick bugfix release without colliding on version numbers. Now **`bp3 release <quest>`** (for full quests) and **`bp3 release --commit <sha>`** (for small bugfixes) compute the next semver version at release time, write a clean "What changed" note, atomically advance `master` + create the tag, cut a GitHub Release whenever the repo lives on GitHub (or keep an annotated git tag locally), and—for `bp3` itself—refresh `~/.local` strictly at that tagged release so downstream repos like `predictor` auto-sync their skills/hooks cleanly the next time a session starts.

## Context

Owner requests & settled sign-offs (2026-11-23):
- Top-level **`bp3 release`** CLI door supporting both **`bp3 release <quest>`** (quest promotion tied to `major | minor | patch | none`, declared in `QUEST.md` `bump:` and overrideable via `--bump`) and **`bp3 release --commit <sha>`** (small bugfixes without a quest, defaulting to `patch`). Owner signed off adding `bp3 release` to `CONSTRAINTS.md` (`"Top-level bp3 release <quest> AND bp3 release --commit <sha> (defaults to patch bump; sign off adding bp3 release to CONSTRAINTS.md)"`, 2026-11-23).
- Automatic **GitHub Release** when a GitHub remote is configured, or **annotated git tag** when local/non-GitHub (`--no-gh` forces local tag).
- Atomic **CAS tagging at release time** so parallel-ly landed quests (and hotfixes) never collide on pre-baked version numbers.
- Simple **"What changed"** update stored verbatim in the annotated tag message and GitHub Release body (no `CHANGELOG.md` merge conflicts).
- **Forward-only**: bump forward from the latest `vX.Y.Z` tag (`v0.2.0` in `bp3`, `0.0.0` in untagged repos); zero retroactive tagging.
- **Tag-gated local auto-update**: `bp3 release` in `bp3` self mode updates `~/.local` strictly on released tags (never untagged commits), and host repos like `~/m/predictor` auto-sync & auto-commit `chore(bp3): sync skills/hooks to v<tag>` on `SessionStart` ONLY when the working tree is clean and a newer tag is installed (warning `W_BP3_UPDATE_AVAILABLE` if dirty).
- Supersedes `version.1` in the unstarted [2026-11-22-bp3-is-static-across-downstream-repo-worktrees](../2026-11-22-bp3-is-static-across-downstream-repo-worktrees/QUEST.md).

Measured ground (read 2026-11-23):

| Fact | Source |
|---|---|
| `bp3` has one tag (`v0.2.0` at `fcfce07`, 2026-11-14) and `let bp3_version = "0.2.0"` | `git tag -l`, `src/quest/gitx.ml:3` |
| `~/.local/bin/bp3-q` reports `0.2.0` (installed `Nov 23 02:38`) and `~/.local/share/bp3/skills/` still carries retired `trial` instead of `warden` | `~/.local/bin/bp3-q --version`, `ls ~/.local/share/bp3/skills` |
| `~/m/predictor` has git-tracked `.agents/skills/` and `.pi/skills/` from `Nov 20` (missing both `induct-inline-yolo` and `warden`) and `.claude/skills/` from `Nov 23 02:38` (missing `warden`) | `ls` & `git ls-files` in `~/m/predictor` (2026-11-23) |
| `Hooks.handle` (`src/quest/hooks.ml:252-257`) gates on `Sys.file_exists (gate_root/bin/bp3)`, causing `bp3 q hooks` to exit early (`"not a bp3 repo"`) in host repos like `predictor` | `src/quest/hooks.ml:252-257` |
| `scripts/release-check`, `scripts/release-publish`, and `scripts/install-bp3.sh` exist (`make release` / `make publish` / `make install`), but nothing runs at quest promotion or stamps `share/bp3/RELEASE` | `scripts/release-*`, `scripts/install-bp3.sh`, `Makefile:46-65` |
| `bin/bp3` has no `release` door; `Store.reserved_slugs` already lists `"release"` (`store.ml:24`) | `bin/bp3:368-396`, `src/quest/store.ml:24` |
| `quest_view` already computes `rollup = "landed"` and `fin = "goal_fin"` when all nodes are `landed` or `deleted` | `src/quest/render.ml:102-109` |
| `test/release.sh:41` and `test/g.sh:71,670,678` hardcode `0.2.0` (and `0.3.0` as minor-ahead), so the first bump to `0.3.0` would break `make check-full` unless unpinned | `test/release.sh:41`, `test/g.sh:71,670,678` |
| `Warden_io.commit_is_status_only` only exempts `docs/quests/*/{QUEST,LOG,FEEDBACK}.md` and `trial/`; a release commit touching `src/quest/gitx.ml` would false-positive `post_land_bugfix` | `src/warden/warden_io.ml:77-98` |
| `scripts/check-gates` pins `make -n check` and `make -n check-full` as an exact allowlist (tested by `test/check-tiers.sh:68-80`) | `scripts/check-gates:46-54`, `test/check-tiers.sh:68-80` |
| 8 pre-`2026-11-22` historical `QUEST.md` files still carry `status: proposed` with no `bump:`; all quests dated `>= 2026-11-22` carry `bump: minor` | `docs/quests/*/QUEST.md` scan (2026-11-23) |
| `git version 2.56.0` is installed, supporting atomic `git update-ref --stdin` transactions (`start`/`update`/`create`/`commit`) and `git mktag` | `git --version` (2026-11-23) |

## Terms

| Term | Meaning |
|---|---|
| `bp3 release` | top-level CLI door (`bin/bp3` -> `main.exe release ...`, signed into `CONSTRAINTS.md:49`): supports quest mode (`bp3 release <quest>`) and commit mode (`bp3 release --commit <sha>`); owner-gated (`BP3_DECIDER=human`, except read-only `--dry-run`) |
| `bump` | semver increment level `major \| minor \| patch \| none`, declared in `QUEST.md` frontmatter (`bump:`) for quests and overrideable via `--bump <level>`; commit mode defaults to `patch` (refuses `none`) |
| `Release` | pure OCaml module `src/quest/release.ml` in `bp3_quest`: semver parsing/bumping, GitHub remote URL parsing, `QUEST.md` frontmatter/TL;DR extraction & status rewrite, `gitx.ml`/`VERSION` rewriter, rendered-tag parsing, auto-sync predicate, and deterministic "What changed" rendering (quest + commit modes) |
| `Release_io` | git/gh/install I/O module `src/quest/release_io.ml` in `bp3_quest`: preflight checks, plumbing commit + `git mktag`, atomic CAS via `git update-ref --stdin`, clean worktree sync, quest ledger `promote` line, optional GitHub push + `gh release create`, and self-mode tag-gated `$PREFIX` install |
| atomic CAS transaction | single `git update-ref --stdin` transaction (`start` / `update refs/heads/<target> <new> <old>` / `create refs/tags/<tag> <tag_obj>` / `commit`); all-or-nothing under git ref locks — concurrent releaser fails cleanly with `E_STALE_WORLD` |
| `release_kind` | verdict & ledger string: `"github"` (tag + push + `gh release create`), `"git_tag"` (local annotated git tag only), or `"none"` (`bump: none` on a quest, branch promoted with no tag) |
| What changed | deterministic Markdown body rendered by `Release.render_what_changed` (quest mode: `QUEST.md` H1/TL;DR + landed nodes) or `Release.render_commit_what_changed` (commit mode: commit subject/body + commits since previous tag), stored verbatim as both the annotated tag message and GitHub Release body |
| `--publish-only` | recovery flag on `bp3 release <quest>` (or `bp3 release --tag <vX.Y.Z> --publish-only`): for a release already tagged locally, pushes `<target>` + `<tag>` (non-force) and runs publish-once `gh release create` using the annotated tag's body |
| `share/bp3/RELEASE` | JSON file `{"tag":"v<ver>","version":"<ver>","source":"<repo>","commit":"<sha>"}` written by `scripts/install-bp3.sh` into `$PREFIX/share/bp3/RELEASE` strictly from tagged releases |
| rendered tag stamp | `(v<ver>)` embedded inside `<!-- GENERATED from skills/<name>/SKILL.md (v<ver>) by: bp3 skills install ... -->` by `bin/bp3 skills install` when `share/bp3/RELEASE` exists |
| host auto-sync | `SessionStart` check in `src/quest/hooks.ml` for host repos (`repo_mode = "host"`): when `share/bp3/RELEASE`'s tag is newer than any rendered skill dir (or legacy unversioned renders exist) and the tree is clean on a normal branch, runs installed `bp3 skills install --harness=all` and commits `chore(bp3): sync skills/hooks to <tag>` (`--no-verify`); if dirty/detached/rebasing, touches nothing and emits `W_BP3_UPDATE_AVAILABLE` |
| `scripts/check-bump` | bash lint script in `make lint` enforcing `bump: major\|minor\|patch\|none` on every `docs/quests/*/QUEST.md` with `date >= 2026-11-22` and `status: proposed\|active` |
| `RELEASING.md` | root doc defining the bump-meaning table, forward-only rule, `bp3 release <quest>` + `bp3 release --commit <sha>` flows, and tag-gated local auto-sync |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `<quest>` | positional arg to `bp3 release <quest>` | mutually exclusive with `--commit` (and `--tag`) |
| `--commit <sha>` | CLI flag | commit-mode bugfix release (no quest required); defaults `--bump` to `patch` |
| `--bump <level>` | CLI flag (`major \| minor \| patch \| none`) | wins over `QUEST.md` `bump:` in quest mode; defaults to `patch` in commit mode (`none` refused in commit mode) |
| `bump:` in `QUEST.md` | `docs/quests/<quest>/QUEST.md` frontmatter (source commit tree, fallback working tree) | used when `--bump` is omitted in quest mode; validated by `scripts/check-bump` for `date >= 2026-11-22` |
| `--target <branch>` | CLI flag | defaults to `master` if `refs/heads/master` exists, else `main` |
| `--remote <name>` | CLI flag | defaults to `origin`; inspected via `git remote get-url <remote>` for GitHub detection |
| `--reason <text>` | CLI flag | optional; defaults to `"release <quest>"` or `"release <sha7>"` |
| `--no-gh` | CLI flag | forces local annotated git tag only even when a GitHub remote exists (no push, no `gh` call) |
| `--no-install` | CLI flag | skips self-mode local `$PREFIX` install after tagging (`BP3_RELEASE_NO_INSTALL=1` env equivalent) |
| `--dry-run` | CLI flag | read-only preview: computes next tag, `release_kind`, and "What changed"; mutates nothing; does not require `BP3_DECIDER=human` |
| `--publish-only` | CLI flag | recovery mode (with `<quest>` or `--tag vX.Y.Z`): pushes `<target>` + `<tag>` and creates missing GitHub Release |
| `--format json\|table` | CLI flag | defaults to `json` |
| `BP3_DECIDER` | env var | must equal `human` for any non-`--dry-run` release (`E_HUMAN_REQUIRED`) |
| `PREFIX` / `BP3_NO_AUTO_SYNC` | env vars | `PREFIX` defaults to `$HOME/.local`; `BP3_NO_AUTO_SYNC=1` disables `SessionStart` auto-sync in host repos |
| repo tags `refs/tags/v*` | git repo | highest valid `vX.Y.Z` tag is the baseline (`0.0.0` if none; non-semver tags ignored) |

## Outputs

| Output | Shape |
|---|---|
| `bp3 release ...` (JSON, exit 0) | `{"ok":true,"mode":"quest"\|"commit","quest":"<q>"\|null,"state":"landed"\|null,"target":"master","previous_tag":"v0.2.0"\|null,"version":"0.3.0"\|null,"tag":"v0.3.0"\|null,"bump":"minor","commit":"<sha>","release_kind":"github"\|"git_tag"\|"none","repo":"owner/repo"\|null,"release_url":"<url>"\|null,"installed_prefix":"<dir>"\|null,"dry_run":false,"notes":"<what changed>"}` |
| `bp3 release ... --format table` | compact summary table + rendered `notes` block |
| git refs (local CAS) | `refs/heads/<target>` advanced to `<new_tip>`, `refs/tags/<tag>` created as annotated tag (unless `bump: none`), plus quest ledger `promote` line in quest mode |
| GitHub Release (when GitHub remote & not `--no-gh` & `bump != none`) | non-force `git push <remote> refs/heads/<target> refs/tags/<tag>` + publish-once `gh release create <tag> --repo <owner/repo> --title "<tag> — <title>" --notes "<notes>"` |
| `$PREFIX` local install (self mode, tagged release, unless `--no-install`) | builds tagged binary + installs to `$PREFIX/bin/{bp3,bp3-q}` and `$PREFIX/share/bp3/` + writes `$PREFIX/share/bp3/RELEASE` |
| Host `SessionStart` auto-sync | on clean host repo with stale/unversioned renders: runs `bp3 skills install --harness=all`, commits `chore(bp3): sync skills/hooks to <tag>`, reports `auto_sync: {"status":"synced","tag":"v0.3.0","commit":"<sha7>"}` in hook JSON; on dirty/detached/rebasing tree: touches nothing, reports `auto_sync: {"status":"dirty_skipped","installed_tag":"v0.3.0","warning":"W_BP3_UPDATE_AVAILABLE"}` |
| typed refusals (JSON on stdout, exit 1 or 2) | `E_USAGE` (2), `E_NOT_FOUND` (2), `E_COMMIT_MISMATCH` (1), `E_HUMAN_REQUIRED` (1), `E_ILLEGAL_EDGE` (1), `E_NOT_READY` (1), `E_ALREADY_PROMOTED` (1), `E_DIRTY_TREE` (1), `E_BUMP_MISSING` (1), `E_NOT_FAST_FORWARD` (1), `E_STALE_WORLD` (1), `E_REMOTE_REJECTED` (1), `E_RELEASE_EXISTS` (1), `E_GH_FAILED` (1, `facts.local_tagged: true`), `E_INSTALL_FAILED` (1, `facts.local_tagged: true`) |
| `scripts/check-bump` (in `make lint`) | exits 0 when valid; exits 1 naming every offending `docs/quests/<q>/QUEST.md` |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 release 2026-11-23-warden-v0 --dry-run
usage: bp3 init ... (unknown door: release)
$ ls src/quest/release.ml src/quest/release_io.ml scripts/check-bump RELEASING.md
No such file or directory
$ git tag -l 'v*'
v0.2.0
$ ~/.local/bin/bp3-q --version
0.2.0
$ ls ~/.local/share/bp3/RELEASE
No such file or directory
$ grep -n '0.2.0' test/release.sh test/g.sh
test/release.sh:41: [ "$out" = "0.2.0" ] || fail "--version: $out"
test/g.sh:71: ... .bp3_version == "0.2.0" ...
test/g.sh:678: ... .error.facts.binary == "0.2.0" ...
```

Design trace (after quest lands):

```text
# 1. Quest release preview (read-only, no BP3_DECIDER required)
$ ./bin/bp3 release demo-q --dry-run
{"ok":true,"mode":"quest","quest":"demo-q","target":"master","previous_tag":"v0.2.0","version":"0.3.0","tag":"v0.3.0","bump":"minor","release_kind":"git_tag","dry_run":true,"notes":"# v0.3.0 — ..."}

# 2. Quest release (local-only repo -> atomic CAS + annotated tag, clean tree)
$ BP3_DECIDER=human ./bin/bp3 release demo-q
{"ok":true,"mode":"quest",...,"tag":"v0.3.0","release_kind":"git_tag","dry_run":false,...}
$ git rev-parse v0.3.0^{commit} master && git status --short   # same SHA, empty status

# 3. Commit-hash hotfix release (no quest required, defaults to patch!)
$ BP3_DECIDER=human ./bin/bp3 release --commit <fix_sha>
{"ok":true,"mode":"commit","quest":null,"previous_tag":"v0.3.0","version":"0.3.1","tag":"v0.3.1","bump":"patch","release_kind":"git_tag",...}

# 4. Parallel quests Q1 & Q2: atomic CAS + fast-forward serialization -> v0.4.0 then v0.5.0
$ BP3_DECIDER=human ./bin/bp3 release q1        # -> v0.4.0
$ BP3_DECIDER=human ./bin/bp3 release q2        # -> E_NOT_FAST_FORWARD (exit 1)
$ git checkout quest/q2 && git rebase master && git checkout master
$ BP3_DECIDER=human ./bin/bp3 release q2        # -> v0.5.0 (zero version collision)

# 5. GitHub remote repo (stubbed gh + bare remote): push + publish-once gh release + --publish-only recovery
$ BP3_DECIDER=human ./bin/bp3 release demo-gh   # -> release_kind: "github", gh release created
# On gh failure -> E_GH_FAILED {local_tagged:true}; re-run with --publish-only -> ok:true

# 6. Tag-gated local auto-sync (self release -> $PREFIX/share/bp3/RELEASE -> clean host repo auto-syncs on SessionStart)
$ PREFIX=$S BP3_DECIDER=human ./bin/bp3 release demo-self
# installs $S/bin/{bp3,bp3-q} and $S/share/bp3/RELEASE {"tag":"v0.3.0",...}
# In clean host fixture repo (stale unversioned skills like predictor):
$ echo '{"hook_event_name":"SessionStart","session_id":"s1"}' | $S/bin/bp3 q hooks
# auto-runs skills install --harness=all, commits "chore(bp3): sync skills/hooks to v0.3.0",
# stamps (v0.3.0) in rendered SKILL.md headers; second SessionStart is a fast no-op;
# on a dirty host repo, touches nothing and emits W_BP3_UPDATE_AVAILABLE;
# an untagged commit in bp3 NEVER updates $S or triggers host sync!

# 7. Lint, Warden clean, and unpinned full gate
$ ./bin/bp3 warden demo-self --no-sessions | jq '.counts.by_rule.post_land_bugfix // 0'   # 0
$ make check-full                                                                        # exit 0
```

## Goal and why

Unify quest promotion, hotfix bugfix releases, and downstream local `bp3` updates behind one atomic, tag-gated mechanism: **`bp3 release`**. Why:
1. `bp3` has sat at `v0.2.0` for 263+ commits because cutting a release was a manual side-quest detached from promoting work.
2. Small bugfixes shouldn't require inventing a full quest just to cut a patch tag.
3. Parallel quests cannot safely pre-assign version numbers on their branches; computing and locking the version atomically at release time (`git update-ref --stdin`) makes parallel landing conflict-free.
4. Local downstream repos like `~/m/predictor` silently fall weeks behind because nothing installs tagged releases automatically or refreshes stale skill renders safely on released tags (while mid-flight untagged commits must NEVER silently push half-baked changes into downstream repos).

## Success picture

- `src/quest/release.ml` implements pure semver/tag/remote/frontmatter/notes/sync logic with full unit + QCheck2 coverage (`test/unit/test_release.ml`).
- Top-level `bp3 release <quest>` and `bp3 release --commit <sha>` work end-to-end in both `self` mode (`bp3`) and `host` repos, with atomic CAS ref updates (`E_STALE_WORLD` / `E_NOT_FAST_FORWARD`), GitHub Release vs. local annotated tag selection, `--publish-only` recovery, `CONSTRAINTS.md` owner-signed surface row, and zero Warden `post_land_bugfix` false positives.
- `scripts/check-bump` enforces `bump:` forward-only (`date >= 2026-11-22`) inside `make lint`, `RELEASING.md` documents the contract, and `test/release.sh` + `test/g.sh` pass dynamically after bumping past `0.2.0`.
- Tag-gated local auto-sync (`sync.1`) refreshes `$PREFIX` strictly on `bp3 release` tags (never untagged commits), stamps `(v<ver>)` in rendered skills, and safely auto-syncs + commits `chore(bp3): sync skills/hooks to v<tag>` in clean host repos on `SessionStart` (warning `W_BP3_UPDATE_AVAILABLE` when dirty).
- `/quest`, `/warden`, and `/using-bp3` skills (and all renders) reflect `bump:` and `bp3 release`.
- Promoting this quest itself via `BP3_DECIDER=human ./bin/bp3 release 2026-11-23-quest-promote-release` cuts `v0.3.0` on `whyczz/bp3`, updates `~/.local` to `v0.3.0`, and lets `~/m/predictor` auto-sync cleanly to `v0.3.0` on its next session start.

## Scope

| In | Out |
|---|---|
| `src/quest/release.ml` + `test/unit/test_release.ml` (pure quest + commit release math, remote parser, frontmatter/version rewriter, rendered-tag parser, "What changed" renderer) | Retroactively tagging historical quests or commits between `v0.2.0` and `HEAD` |
| Top-level `bp3 release <quest>` AND `bp3 release --commit <sha>` (`bin/bp3`, `src/quest/release_io.ml`, `main.ml`, `store.ml`, `CONSTRAINTS.md` surface sign-off, completions, `AGENTS.md`/`CLAUDE.md`, `Warden_io` exemption, `test/release-door.sh`) | Uploading compiled binary assets inside `bp3 release` (`make publish` stays for GitHub binary asset distribution) |
| Tag-gated local auto-update (`sync.1`): self-mode `bp3 release` installs tagged build into `$PREFIX` + writes `share/bp3/RELEASE`; `bin/bp3 skills install` stamps `(v<ver>)`; `hooks.ml` `SessionStart` auto-syncs & commits clean host repos (warns when dirty); `test/release-sync.sh` | Network auto-update / fetching from GitHub in `SessionStart` (local `$PREFIX` only) or auto-updating on untagged commits |
| `scripts/check-bump` in `make lint` + `scripts/check-gates` + `test/check-tiers.sh` + `RELEASING.md` + unpinning `0.2.0`/`0.3.0` in `test/release.sh` & `test/g.sh` + marking `2026-11-22` `version.1` superseded | Committed `CHANGELOG.md` file (notes live in annotated tag + GitHub Release body) |
| Skill updates (`skills/{quest,warden,using-bp3}/SKILL.md`, all harness renders, `test/skills.sh`) | Non-GitHub forge APIs (GitLab/Gitea/Codeberg fall back cleanly to local annotated git tag) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):**
  - Languages & libraries: OCaml (`stdlib`, `unix`, `str`, `yojson`, `ounit2`, `qcheck-core`, `qcheck-ounit`), Bash (`posix`, `git`, `jq`, `sed`, `awk`, `gh`), Zsh/Bash completions (existing files), Markdown docs & skills. Zero new languages or external libraries (`gh` is already signed in `CONSTRAINTS.md:22`).
  - Surface addition: `cli.1` adds **`bp3 release`** to `bp3 CLI` in `CONSTRAINTS.md:49` with a dated owner-words Sign-off log row quoting the owner's 2026-11-23 approval (`"Top-level bp3 release <quest> AND bp3 release --commit <sha> (defaults to patch bump; sign off adding bp3 release to CONSTRAINTS.md)"`).
- **Common-sense pass (`CONTEXT.md`):**
  - Owner-gated promotion (`CONTEXT.md:44`, checked `2026-11-19`, `< 90d`): `bp3 release` enforces `BP3_DECIDER=human` on every real release (`--dry-run` stays read-only).
  - Deterministic scripts separate from LLM judgment (`CONTEXT.md:23`, checked `2026-11-19`, `< 90d`): version math, CAS ref locks, tag creation, "What changed" extraction, and tag-gated local sync are 100% deterministic OCaml/bash.
  - Trunk-based / parallel batching tension (`CONTEXT.md:85`, checked `2026-11-19`, `< 90d`): deferring version assignment to CAS release time removes version-number merge conflicts between parallel quests and bugfixes.

## Human touchpoints

| When | Owner |
|---|---|
| Approve this Quest frame (or `/red-ink` first) | owner |
| Dispose `/warden` proposals and run `BP3_DECIDER=human ./bin/bp3 release 2026-11-23-quest-promote-release` at `goal_fin` (cuts `v0.3.0`, refreshes `~/.local` to `v0.3.0`) | owner |

## Nodes

### Milestone: core

| Node | TL;DR |
|---|---|
| [core.1 - release-engine](nodes/node-core-1-release-engine/NODE.md) | Pure OCaml `src/quest/release.ml` (semver/tag math, GitHub URL parser, `QUEST.md` frontmatter/TL;DR parser & status updater, `gitx.ml`/`VERSION` rewriter, rendered-tag parser & auto-sync predicate, quest + commit "What changed" renderers) + `test/unit/test_release.ml` (unit + QCheck2 laws) |

### Milestone: lint

| Node | TL;DR |
|---|---|
| [lint.1 - bump-lint-and-docs](nodes/node-lint-1-bump-lint-and-docs/NODE.md) | `scripts/check-bump` wired into `Makefile` + `scripts/check-gates` + `test/check-tiers.sh`, root `RELEASING.md`, unpin `0.2.0`/`0.3.0` in `test/release.sh` & `test/g.sh` (proven at `0.3.0`), mark `2026-11-22` `version.1` superseded |

### Milestone: cli

| Node | TL;DR |
|---|---|
| [cli.1 - release-door](nodes/node-cli-1-release-door/NODE.md) | Top-level `bp3 release <quest>` & `bp3 release --commit <sha>` (`bin/bp3`, `src/quest/release_io.ml`, `main.ml`, `store.ml`), atomic `git update-ref --stdin` CAS, GitHub Release vs. local tag, `--publish-only`, `--dry-run`, `--no-gh`, `CONSTRAINTS.md` sign-off row, `Warden_io` release-commit exemption, completions, `AGENTS.md`/`CLAUDE.md`, `test/release-door.sh` |

### Milestone: sync

| Node | TL;DR |
|---|---|
| [sync.1 - tag-gated-local-sync](nodes/node-sync-1-tag-gated-local-sync/NODE.md) | Tag-gated local auto-update: `scripts/install-bp3.sh` writes `$PREFIX/share/bp3/RELEASE`, self-mode `bp3 release` auto-installs tagged build to `$PREFIX` (opt-out `--no-install`), `bin/bp3 skills install` stamps `(v<ver>)`, `hooks.ml` `SessionStart` auto-syncs & commits clean host repos (warns `W_BP3_UPDATE_AVAILABLE` if dirty; never touches untagged commits) + `test/release-sync.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - release-skills](nodes/node-skills-1-release-skills/NODE.md) | Skill node: update `skills/{quest,warden,using-bp3}/SKILL.md` (`bump:`, `bp3 release <quest>`, `bp3 release --commit <sha>`, tag-gated auto-sync), re-render all harnesses (`./bin/bp3 skills install --harness=all`), pin assertions in `test/skills.sh` |

## Scorecard

| Metric | Target | Read from |
|---|---|---|
| Nodes at `node_fin` | 5 of 5 | `bp3 q r 2026-11-23-quest-promote-release` |
| Pure unit + property tests (`test_release.ml`) | 100% pass in `dune test` (`make check`) | `make check` |
| Release fixture suite (`test/release-door.sh`) | quest + commit modes, local tag, GitHub Release, parallel CAS race (`E_STALE_WORLD` + `E_NOT_FAST_FORWARD`), `--publish-only`, `--dry-run`, `--no-gh`, `major`/`minor`/`patch`/`none`, self & host modes, Warden 0 FP | `make check-full` |
| Local auto-sync fixture suite (`test/release-sync.sh`) | self-mode release installs `$PREFIX` + `RELEASE`, clean host repo auto-syncs & commits on `SessionStart`, dirty/detached host repo skips + warns `W_BP3_UPDATE_AVAILABLE`, untagged commits never sync | `make check-full` |
| First live release | `v0.3.0` tagged on `master` + GitHub Release on `whyczz/bp3` + `~/.local` updated to `v0.3.0` (`share/bp3/RELEASE`) | live `bp3 release` at `goal_fin` |

## Risks and red chair

- **Strongest attack 1 — Half-released state when push, `gh release create`, or local install fails after local CAS (major):**
  - *Attack:* Local atomic CAS moves `master` + creates `v0.3.0`, then `git push`, `gh release create`, or `make install` fails. Re-running `bp3 release` refuses `E_ALREADY_PROMOTED`, stranding the release.
  - *Settled in design:* Added `--publish-only` (`cli.1`) for pushing + creating the missing GitHub Release from the annotated tag; remote/gh/install failures emit `E_REMOTE_REJECTED` / `E_GH_FAILED` / `E_INSTALL_FAILED` with `facts.local_tagged: true` and exact recovery command.
- **Strongest attack 2 — Host `SessionStart` auto-sync corrupts an in-flight repo or hangs on host pre-commit hooks (major):**
  - *Attack:* If `SessionStart` auto-sync runs `bp3 skills install` on a dirty working tree, detached HEAD, or mid-rebase repo—or triggers `predictor`'s `.githooks/pre-commit` (`dune build @fmt`)—it breaks the user's work or stalls session startup. And in `src/quest/hooks.ml:252-257`, host repos currently hit `"not a bp3 repo"` early because `bin/bp3` isn't tracked there!
  - *Settled in design:* `sync.1` runs the host auto-sync check BEFORE the self-only `bin/bp3` gate; it refuses to mutate git unless `worktree_dirty () = false`, `HEAD` is on a symbolic branch (`refs/heads/*`), and neither `MERGE_HEAD` nor `rebase-merge`/`rebase-apply` exists; it stages ONLY `.claude/`, `.agents/`, `.pi/`, `.muse/`; it commits with `--no-verify` (generated markdown/JSON only, zero code touched); and `BP3_NO_AUTO_SYNC=1` is an instant kill-switch. Dirty/detached repos get `W_BP3_UPDATE_AVAILABLE` with zero filesystem edits.
- **Strongest attack 3 — Plumbing `update-ref` desyncs a checked-out target branch (major):**
  - *Settled in design:* `cli.1` inspects `git worktree list --porcelain` before CAS (refusing `E_DIRTY_TREE` if current or target worktree is dirty) and syncs verified-clean target worktrees (`git -C <wt> reset --hard --quiet HEAD`) right after CAS commits.
- **Strongest attack 4 — First bump breaks `make check-full` and triggers Warden `post_land_bugfix` (major):**
  - *Settled in design:* `lint.1` unpins `test/release.sh:41` and `test/g.sh:71,670,678` (proving green at `0.3.0`), scopes `scripts/check-bump` forward-only (`date >= 2026-11-22`), and `cli.1` exempts `chore(release): v*` commits in `Warden_io.commit_is_status_only`.
- **Attack on source (owner prompts + unstarted `2026-11-22` draft):**
  - *Commit-hash vs quest ambiguity:* Solved cleanly with explicit `--commit <sha>` flag (`bp3 release <quest>` vs `bp3 release --commit <sha>`) — zero ambiguity if a quest slug happens to be hex-like!
  - *Untagged commits must never auto-update downstream repos:* Enforced structurally because `share/bp3/RELEASE` is written ONLY from `scripts/install-bp3.sh` (gated by `scripts/release-check` requiring an annotated tag at HEAD) when `bp3 release` cuts a tag.
  - *Overlap with `2026-11-22` draft (`version.1`):* `lint.1` marks `version.1` superseded by this quest.

## Open questions

None — all design decisions and `CONSTRAINTS.md` surface sign-off settled before approval.

## Node diagram

```text
cohort 1: core.1 (src/quest/release.ml + test_release.ml)   ||   lint.1 (scripts/check-bump + RELEASING.md + unpin tests)
              │                                                       │
              ▼                                                       │
cohort 2: cli.1 (top-level bp3 release <quest> & --commit <sha> + CAS + gh/tag + CONSTRAINTS.md + test/release-door.sh)
              │                                                       │
              ▼                                                       │
cohort 3: sync.1 (tag-gated $PREFIX install + share/bp3/RELEASE + host SessionStart auto-sync + test/release-sync.sh)
              │                                                       │
              └──────────────────────────┬────────────────────────────┘
                                         ▼
cohort 4: skills.1 (skills/{quest,warden,using-bp3}/SKILL.md + renders + test/skills.sh)
                                         │
                                         ▼
release (owner): BP3_DECIDER=human ./bin/bp3 release 2026-11-23-quest-promote-release  ──► v0.3.0 + ~/.local updated
```
