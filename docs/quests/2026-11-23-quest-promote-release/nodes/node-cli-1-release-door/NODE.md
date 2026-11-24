---
date: 2026-11-23
quest: ../../QUEST.md
node: cli.1
status: proposed
---

# cli.1 - release-door: top-level `bp3 release <quest>` & `bp3 release --commit <sha>` with atomic CAS

## TL;DR

Wire the top-level, owner-gated **`bp3 release`** CLI door (`bin/bp3`, `src/quest/release_io.ml`, `src/quest/main.ml`, `src/quest/store.ml`, `CONSTRAINTS.md`, `completions/{_bp3,bp3.bash}`, `AGENTS.md`, `CLAUDE.md`) backed by `Release` (`core.1`). Supports both **`bp3 release <quest>`** (promotes a `goal_fin` quest using `QUEST.md`'s `bump:` or `--bump`) and **`bp3 release --commit <sha>`** (cuts a lightweight bugfix release from a commit hash without a quest, defaulting `--bump` to `patch`). Both build the promote/version commit and annotated tag (`git mktag`) purely in git plumbing, commit `refs/heads/<target>` + `refs/tags/<tag>` in **one atomic `git update-ref --stdin` CAS transaction**, sync verified-clean target worktrees, and—when a GitHub remote exists and `--no-gh` is absent—push non-force and run publish-once `gh release create` (with `--publish-only` recovery). Also adds the owner-signed `bp3 release` row to `CONSTRAINTS.md`, exempts `chore(release): v*` commits in `src/warden/warden_io.ml`, and adds `test/release-door.sh` to `test/suites.tsv`.

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 release 2026-11-23-warden-v0 --dry-run
usage: bp3 init ... (unknown door: release)
$ ./bin/bp3 release -h
usage: bp3 init ... (unknown door: release)
$ ls src/quest/release_io.ml test/release-door.sh
No such file or directory
```

Design trace (after `cli.1` lands):

```text
$ ./bin/bp3 release -h
bp3 release <quest> | bp3 release --commit <sha> ... (help text, exit 0, reads no state)

# Quest mode preview (no BP3_DECIDER needed, read-only)
$ ./bin/bp3 release demo --dry-run
{"ok":true,"mode":"quest","quest":"demo","state":"landed","target":"master","previous_tag":null,"version":"0.1.0","tag":"v0.1.0","bump":"minor","commit":"<sha>","release_kind":"git_tag","repo":null,"release_url":null,"installed_prefix":null,"dry_run":true,"notes":"# v0.1.0 — ..."}

# Quest mode local-only host repo -> atomic CAS + v0.1.0 annotated tag, clean tree, ledger stamped
$ BP3_DECIDER=human ./bin/bp3 release demo
{"ok":true,"mode":"quest",...,"version":"0.1.0","tag":"v0.1.0","release_kind":"git_tag","dry_run":false,...}
$ git rev-parse v0.1.0^{commit} master && git status --short   # identical SHA, empty status
$ BP3_DECIDER=human ./bin/bp3 release demo
{"ok":false,"error":{"code":"E_ALREADY_PROMOTED",...}}         # exit 1

# Commit mode bugfix release (no quest required; defaults --bump patch)
$ BP3_DECIDER=human ./bin/bp3 release --commit <fix_sha>
{"ok":true,"mode":"commit","quest":null,"previous_tag":"v0.1.0","version":"0.1.1","tag":"v0.1.1","bump":"patch","release_kind":"git_tag",...}
$ git tag -n99 v0.1.1   # carries commit subject + "What changed"

# Parallel quests Q1 & Q2 branched from master M0:
# Q1 releases -> v0.2.0 (master M0 -> M1)
# Q2 (still on M0) -> E_NOT_FAST_FORWARD (exit 1)
# Q2 rebases onto M1 -> v0.3.0 (never collides with v0.2.0!)
# Concurrent CAS collision (existing tag or moved target) -> E_STALE_WORLD, zero partial ref update

# GitHub remote repo (bare remote + url.<bare>.insteadOf + stubbed gh):
$ BP3_DECIDER=human ./bin/bp3 release demo-gh
{"ok":true,...,"tag":"v0.1.0","release_kind":"github","repo":"whyczz/demo-gh",...}
# Failed gh -> E_GH_FAILED {local_tagged:true}; re-run with --publish-only -> ok:true

# Self-mode repo (src/quest/gitx.ml tracked, --no-install in cli.1 fixture):
$ BP3_DECIDER=human ./bin/bp3 release demo-self --bump major --no-install
{"ok":true,...,"version":"1.0.0","tag":"v1.0.0",...}
$ ./scripts/release-check                                      # prints 1.0.0, exit 0
$ ./bin/bp3 warden demo-self --no-sessions | jq '.counts.by_rule.post_land_bugfix // 0'
0

$ ./test/release-door.sh && ./test/completion.sh && ./test/check-constraints.sh && make check-full
```

```yaml
objective: implement top-level bp3 release (<quest> and --commit <sha>) with atomic CAS, GitHub Release vs local tag, --publish-only recovery, CONSTRAINTS.md sign-off, Warden exemption, and full fixture suite
prove by:
  - ./test/release-door.sh (registered in test/suites.tsv)
  - ./test/completion.sh
  - ./test/check-constraints.sh
  - make check-full
done when: every case in test/release-door.sh, test/completion.sh, and test/check-constraints.sh passes, bp3 warden emits 0 post_land_bugfix on release commits, and make check-full exits 0
```

## Diagram

```text
bp3 release (<quest> | --commit <sha>) [flags]
  │
  ├─ -h / --help ──► print help_release, exit 0
  ├─ --publish-only (<quest> | --tag <vX.Y.Z>) ──► verify BP3_DECIDER=human + local tag exists
  │                                                ──► git push <remote> <target> <tag> (non-force)
  │                                                ──► gh release view (publish-once) ──► gh release create
  │
  └─ quest mode OR commit mode:
       1. Preflight:
          - quest mode: quest exists, not deleted, not already promoted, all nodes terminal (goal_fin)
          - commit mode: commit resolves (E_COMMIT_MISMATCH), bump <> none (E_USAGE)
          - both: BP3_DECIDER=human (unless --dry-run), clean current + target worktrees (E_DIRTY_TREE),
            fast-forward check is_ancestor target_tip source_tip (E_NOT_FAST_FORWARD), legal bump
       2. Compute: latest vX.Y.Z tag ──► Release.next_semver ──► What changed notes
          Detect remote: git remote get-url <remote> ──► Release.parse_github_repo
       3. If --dry-run ──► return verdict JSON (zero mutations)
       4. Plumbing commit (when QUEST.md status!=landed or gitx.ml/VERSION changes):
          read-tree source_tip -> update files -> write-tree -> commit-tree
       5. Plumbing annotated tag (when bump != none): git mktag (message = What changed)
       6. ATOMIC CAS: git update-ref --stdin
            start
            update refs/heads/<target> <new_tip> <old_target_tip>
            create refs/tags/<tag> <tag_obj>          (when bump != none)
            commit
          (on failure ──► E_STALE_WORLD, zero partial writes)
       7. Sync clean worktree(s) holding refs/heads/<target> (git -C <wt> reset --hard --quiet HEAD)
       8. Quest mode only: append quest ledger line (edge="promote", to="landed", tag, bump, target, release_kind)
       9. If GitHub remote and not --no-gh and bump != none:
            git push <remote> refs/heads/<target> refs/tags/<tag>  (fail -> E_REMOTE_REJECTED, local_tagged=true)
            gh release view <tag> --repo <r>                       (exists -> E_RELEASE_EXISTS)
            gh release create <tag> --repo <r> --title ... --notes (fail -> E_GH_FAILED, local_tagged=true)
```

## Pseudocode

```python
def do_release(argv, id):
    opts = parse_release_args(argv)                       # quest | --commit | --tag (publish-only)
    if opts.help:
        print(help_release); return 0
    if opts.publish_only:
        return do_publish_only(opts, id)
    if opts.quest and opts.commit:
        raise E_USAGE("pass either <quest> or --commit <sha>, not both")
    if not opts.quest and not opts.commit:
        raise E_USAGE("expected bp3 release <quest> or bp3 release --commit <sha>")

    if not opts.dry_run and not id.decider_human:
        raise E_HUMAN_REQUIRED

    target = opts.target or detect_default_branch()       # master -> main
    target_tip = ref_tip(f"refs/heads/{target}")          # E_NOT_FOUND

    if opts.quest:
        qs, nodes = load_quest_and_nodes(opts.quest)      # E_NOT_FOUND
        if qs.st == "deleted": raise E_ILLEGAL_EDGE
        if qs.st == "landed" or quest_ledger_has_promote(opts.quest): raise E_ALREADY_PROMOTED
        pending = [n for n in nodes if n.st not in ("landed", "deleted")]
        if not nodes or pending: raise E_NOT_READY(pending_nodes=pending)
        source_tip = resolve_quest_source(opts.quest)     # quest/<q> -> HEAD
    else:
        source_tip = resolve_commit(opts.commit)          # E_COMMIT_MISMATCH

    if not opts.dry_run:
        check_clean_worktree(root)                        # E_DIRTY_TREE
        target_wts = worktrees_on_branch(f"refs/heads/{target}")
        for wt in target_wts: check_clean_worktree(wt)    # E_DIRTY_TREE
    if not is_ancestor(target_tip, source_tip):
        raise E_NOT_FAST_FORWARD(target=target, target_tip=target_tip, source_tip=source_tip)

    prev = Release.latest_semver_tag(list_v_tags())
    bump = resolve_bump(opts, source_tip)                 # quest: --bump or QUEST.md; commit: --bump or patch (refuse none)
    next_v = Release.next_semver(prev, bump)
    tag = Release.format_tag(next_v) if next_v else None
    gh_repo = None if (opts.no_gh or not tag) else Release.parse_github_repo(remote_url(opts.remote))
    release_kind = "none" if not tag else ("github" if gh_repo else "git_tag")
    notes = build_notes(opts, source_tip, tag, prev)

    if opts.dry_run:
        return verdict(ok=True, dry_run=True, ...)

    files = collect_release_files(opts, source_tip, next_v)
    new_tip = commit_tree_plumbing(source_tip, files, msg=release_commit_msg(opts, tag, notes)) if files else source_tip
    tag_obj = git_mktag(new_tip, tag, notes.body) if tag else None

    # Atomic CAS transaction over target branch + new tag
    atomic_update_ref(target, new_tip, target_tip, tag, tag_obj)   # E_STALE_WORLD on loss
    for wt in target_wts:
        git_run(["-C", wt, "reset", "--hard", "--quiet", "HEAD"])
    if opts.quest:
        append_quest_promote_line(opts.quest, ...)
    if gh_repo and tag:
        push_and_create_gh_release(opts.remote, target, tag, gh_repo, notes)
    return verdict(ok=True, dry_run=False, ...)
```

## Tables

| Field | Value |
|---|---|
| Intent | Ship top-level `bp3 release` (quest & commit modes) with atomic CAS, automatic GitHub Release vs. local tag, and Warden compatibility |
| Lane | standard |
| Output | `src/quest/release_io.ml`, `src/quest/main.ml`, `bin/bp3`, `src/warden/warden_io.ml`, `CONSTRAINTS.md` (owner-words Sign-off row for `bp3 release`), `completions/_bp3`, `completions/bp3.bash`, `AGENTS.md`, `CLAUDE.md`, `test/release-door.sh`, `test/suites.tsv`, `test/completion.sh` |
| Acceptance | `test/release-door.sh`, `test/completion.sh`, `test/check-constraints.sh`, and `make check-full` exit 0 |
| Depends on | `core.1 - release-engine` |

Error contract (`bp3 release`):

| Code | Exit | When | Partial state? |
|---|---|---|---|
| `E_USAGE` | 2 | Bad flag, both `<quest>` and `--commit`, missing target arg, `--bump none` in commit mode | None |
| `E_NOT_FOUND` | 2 | Quest or `--target` branch (or `--tag` in `--publish-only`) does not exist | None |
| `E_COMMIT_MISMATCH` | 1 | `--commit <sha>` does not resolve to a commit | None |
| `E_HUMAN_REQUIRED` | 1 | `BP3_DECIDER <> "human"` on non-`--dry-run` call | None |
| `E_ILLEGAL_EDGE` | 1 | Quest is `deleted`, or `--publish-only` on unpromoted/tagless quest | None |
| `E_ALREADY_PROMOTED` | 1 | Quest already has a `promote` ledger edge (without `--publish-only`) | None |
| `E_NOT_READY` | 1 | Quest has 0 nodes or any node not `landed`/`deleted` (`facts.pending_nodes`) | None |
| `E_DIRTY_TREE` | 1 | Current worktree or target branch's checked-out worktree has uncommitted changes | None |
| `E_BUMP_MISSING` | 1 | Quest mode: neither `--bump` nor `QUEST.md` frontmatter provides `bump:` | None |
| `E_NOT_FAST_FORWARD` | 1 | `target_tip` is not an ancestor of `source_tip` (e.g. parallel quest or hotfix promoted first) | None |
| `E_STALE_WORLD` | 1 | Atomic `git update-ref --stdin` lost a concurrent race (target moved or tag exists) | None (atomic abort) |
| `E_REMOTE_REJECTED` | 1 | Non-force `git push` rejected by remote | Local CAS succeeded (`facts.local_tagged: true`); recover via `--publish-only` |
| `E_RELEASE_EXISTS` | 1 | `gh release view <tag>` already exists (publish-once refusal) | Local CAS succeeded |
| `E_GH_FAILED` | 1 | `gh release create` failed (offline, unauthed, CLI missing) | Local CAS succeeded (`facts.local_tagged: true`); recover via `--publish-only` |

## Prose

`bp3 release` mirrors `bp3 warden`'s dispatch pattern in `bin/bp3` (`release) shift; run_q release "$@" ;;`) and `src/quest/main.ml` (`| "release" :: rest -> do_release rest id`), and adds `bp3 release` to `CONSTRAINTS.md:49` with the owner's 2026-11-23 sign-off row. Note `"release"` is already listed in `Store.reserved_slugs` (`src/quest/store.ml:24`).

In `cli.1`, `--no-install` is accepted (and self-mode auto-install is wired in `sync.1` right after `cli.1`, so `cli.1` sets `"installed_prefix": null` cleanly and stays focused on the git/CAS/GitHub release door!).

In `src/warden/warden_io.ml`, extend `commit_is_status_only` so commits whose subject starts with `chore(release): v` or `chore(promote): ` and touch only `{docs/quests/*/{QUEST,LOG,FEEDBACK}.md, src/quest/gitx.ml, VERSION}` never trigger `post_land_bugfix`.

## Tests

- `test/release-door.sh` (fixture tier, registered in `test/suites.tsv` with paths `src/*,bin/bp3,test/release-door.sh`):
  1. Help (`-h`) and `--dry-run` in both quest mode and `--commit` mode (zero mutations, no `BP3_DECIDER` required).
  2. Preflight refusals: `E_HUMAN_REQUIRED`, `E_NOT_READY`, `E_DIRTY_TREE`, `E_BUMP_MISSING`, `E_NOT_FOUND`, `E_COMMIT_MISMATCH`, `E_ILLEGAL_EDGE`, `E_USAGE` (`--bump none` on `--commit`).
  3. Untagged host repo quest release (`bump: minor` -> `v0.1.0`, `git_tag`, annotated tag carries TL;DR + nodes, `QUEST.md` flipped to `landed`, clean `git status`, quest ledger stamped `promote`, second run -> `E_ALREADY_PROMOTED`).
  4. Commit-hash bugfix release (`--commit <sha>` -> default `patch` -> `v0.1.1`; `--bump minor` -> `v0.2.0`; `--bump major` -> `v1.0.0`; annotated tag carries commit subject + "What changed").
  5. Quest `bump: none` promotes branch & flips `QUEST.md` with no tag (`release_kind: "none"`).
  6. Parallel CAS: `Q1` and `Q2` branched from `M0`; `Q1` releases -> `v0.2.0`; `Q2` refuses `E_NOT_FAST_FORWARD`; `Q2` rebases onto `master` and releases -> `v0.3.0`; concurrent CAS collision (existing tag or moved target) refuses `E_STALE_WORLD` with zero partial ref updates.
  7. GitHub remote mode (bare remote + `url.<bare>.insteadOf https://github.com/whyczz/demo.git` + stubbed `gh`): pushes `master` + tag + creates GitHub Release; `--no-gh` skips push/gh; failed `gh` returns `E_GH_FAILED` with `local_tagged: true`, then `--publish-only` succeeds; duplicate release refuses `E_RELEASE_EXISTS`.
  8. Self-mode repo (`src/quest/gitx.ml` + `bin/bp3` tracked): updates `bp3_version`, `scripts/release-check` passes at new version, `bp3 warden <quest> --no-sessions` emits 0 `post_land_bugfix` findings.
  9. Host repo with tracked `VERSION` file: updates `VERSION` inside the release commit.
- `test/completion.sh`: assert `release` completes at top level and `--commit`, `--bump`, `--no-gh`, `--no-install`, `--dry-run`, `--publish-only` complete under `bp3 release`.
- `test/check-constraints.sh`: green with new `CONSTRAINTS.md` sign-off row.
