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
BP3_DECIDER=human bp3 release <quest> [--bump major|minor|patch|none] [--no-gh] [--no-install]
```

### 2. Cut a bugfix release from a commit hash (no quest required)

```sh
# Defaults to --bump patch; supports --bump minor|major as well:
BP3_DECIDER=human bp3 release --commit <sha> [--bump patch|minor|major] [--no-gh]
```

### 3. Parallel quests and atomic CAS

Quest branches never hardcode the next version number. At release time, `bp3 release`
verifies `target` is an ancestor of the source commit (`E_NOT_FAST_FORWARD` if another
quest promoted first—rebase, re-verify, and retry) and updates `refs/heads/<target>`
and `refs/tags/v<new>` in **one atomic `git update-ref --stdin` transaction**
(`E_STALE_WORLD` on a concurrent race, with zero partial ref writes).

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
