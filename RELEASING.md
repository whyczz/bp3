# Releasing bp3 (and bp3-managed repos)

Every quest declares its semver `bump:` in `QUEST.md` frontmatter at framing,
enforced forward-only (`date >= 2026-11-22`) by `scripts/check-bump` in `make lint`.
Releases are cut **at release time** via `bp3 release`, never pre-baked onto quest branches.

## Bump meanings

| Bump | Means | Examples |
|---|---|---|
| `major` | Breaking change: ledger/state semantics change (old fold reads lines differently) OR breaking CLI/public contract removal or rename (`M+1.0.0`; cuts `1.0.0` from `0.x`) | ledger field renamed, CLI door/flag removed (`bp3 g` -> `bp3 q`) |
| `minor` | Backwards-compatible feature or addition (`M.m+1.0`; before `1.0`, breaking changes may optionally ride `minor` if staying `0.x`) | new CLI verb/flag, new skill, new optional JSON field, new Warden plug |
| `patch` | Bug fix or internal improvement with no contract change (`M.m.p+1`; default for `bp3 release --commit <sha>`) | small bugfix commit, performance, help/table polish |
| `none` | Docs, tests, or quest frames only — promotes quest branch and marks `QUEST.md` `landed` with no tag or GitHub Release (quest mode only) | quest frame, typo fix, test-only refactor |

## Forward-only rule

`bp3 release` reads the highest valid `vX.Y.Z` tag in the repository (`0.0.0` if
untagged) and increments from there. Historical commits and quests before adoption
are never retroactively tagged.

## Cutting a release

All real releases require `BP3_DECIDER=human`; `--dry-run` is read-only and works without it.

### 1. Promote and release a finished quest (`goal_fin`)

```sh
# Preview version, release_kind, and "What changed" notes (read-only):
bp3 release <quest> --dry-run

# Promote, flip QUEST.md status -> landed, sync version file, atomically CAS
# master + annotated tag vX.Y.Z, and publish a GitHub Release when a GitHub
# remote exists (or local annotated git tag only otherwise):
BP3_DECIDER=human bp3 release <quest> [--bump major|minor|patch|none] [--ff-only] [--no-gh] [--no-install]
```

### 2. Cut a bugfix release from a commit hash (no quest required)

```sh
# Defaults to --bump patch; supports --bump minor|major as well:
BP3_DECIDER=human bp3 release --commit <sha> [--bump patch|minor|major] [--ff-only] [--no-gh]
```

### 3. Parallel quests and Tiered CAS (`merge-tree`)

Quest branches never hardcode the next version number. At release time, `bp3 release`
keeps strict fast-forward (`strategy: "fast_forward"`) as the instant fast path when
`target` is an ancestor of `source_tip`. When `target` moved concurrently on disjoint
work (unless `--ff-only` is passed, which refuses `E_NOT_FAST_FORWARD`), `bp3 release`:

1. Computes an in-memory 3-way merge via `git merge-tree --write-tree` (refusing
   `E_MERGE_CONFLICT` with `facts.conflicts` on textual conflict, `target` untouched).
2. Classifies `merge_base..target` drift: `doc_only` (`docs/icebox/**`, `docs/dossiers/**`,
   `docs/quests/<other>/**`) runs fast `make lint` when present; `code` drift runs
   `BP3_RELEASE_VERIFY_CMD` (or `make check-full` when present) inside an ephemeral
   detached worktree (always removed on exit; failing emits `E_VERIFY_FAILED`, `target`
   untouched).
3. Assembles a 2-parent plumbing merge commit (`-p target -p source_tip`, preserving every
   graded node commit SHA as `HEAD^2`) and updates `refs/heads/<target>` and
   `refs/tags/v<new>` in **one atomic `git update-ref --stdin` transaction**, retrying
   up to 3 times on concurrent movement (re-reading tags each attempt; `E_STALE_WORLD`
   if exhausted, with zero partial ref writes).

### 4. Recovery (`--publish-only`)

If local CAS tagging succeeded and pushing or `gh release create` failed (offline,
expired auth, remote moved), reconcile/auth and recover without re-tagging:

```sh
BP3_DECIDER=human bp3 release <quest> --publish-only
# or for a commit release:
BP3_DECIDER=human bp3 release --tag vX.Y.Z --publish-only
```

### 5. User-global skills/hooks install & binary assets

- In `bp3` self mode, `bp3 release` (unless `--no-install`) builds and installs the
  tagged release to `$PREFIX` (`~/.local`), stamps `$PREFIX/share/bp3/RELEASE`,
  and refreshes user-global `CORE_SKILLS` and hooks under `~/` (`~/.claude`,
  `~/.gemini/config`, `~/.pi/agent`, `~/.codex`, `~/.muse`). Untagged commits
  never touch `$PREFIX`.
- Downstream host repos stay in lockstep automatically via user-global skills and
  hooks and opt in via `backpack.toml` (`bp3 init-repo`). Host `SessionStart`
  auto-commit sync is retired; if legacy repo-local generated skill copies remain
  in a host repo, `bp3 q hooks` emits a read-only `W_LOCAL_SKILLS_LEGACY` warning
  pointing to `bp3 skills prune-local` and never commits to host git branches.
- To build and attach binary artifacts to an existing GitHub Release in `bp3`, run
  `make release` / `make publish`.
