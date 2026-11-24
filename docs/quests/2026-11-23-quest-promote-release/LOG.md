# 2026-11-23-quest-promote-release — Run Log

## Nodes

| Node | State | Cycles | Commit | Notes |
|---|---|---|---|---|
| `node-core-1-release-engine` | landed (`node_fin`) | 1 | `debf391` | pure OCaml `src/quest/release.ml` + 12 OUnit2/QCheck2 tests (`test/unit/test_release.ml`) |
| `node-lint-1-bump-lint-and-docs` | landed (`node_fin`) | 1 | `4ac8353` | `scripts/check-bump` in `make lint`, `RELEASING.md`, unpinned `test/release.sh` & `test/g.sh` (verified at `0.3.0`), `2026-11-22` `version.1` marked superseded |
| `node-cli-1-release-door` | landed (`node_fin`) | 1 | `3ca30c5` | top-level `bp3 release` (`<quest>` & `--commit`), atomic `git update-ref --stdin` CAS, GitHub Release vs annotated tag, `--publish-only`, `CONSTRAINTS.md` sign-off, `Warden_io` exemption, `test/release-door.sh` (26 checks) |
| `node-sync-1-tag-gated-local-sync` | landed (`node_fin`) | 1 | `8e7d822` | tag-gated `$PREFIX` install + `share/bp3/RELEASE`, `(v<ver>)` skill header stamp, clean-only host `SessionStart` auto-sync (`hooks.ml`), `test/release-sync.sh` (10 checks) |
| `node-skills-1-release-skills` | landed (`node_fin`) | 1 | `b8e42ae` | updated `skills/{quest,warden,using-bp3}/SKILL.md` + all harness renders + `test/skills.sh` (579 assertions) |

## Build notes

- Activated `2026-11-23` under `/induct-inline-yolo` (owner-approved frame + `CONSTRAINTS.md` surface sign-off for `bp3 release`).
- All 5/5 nodes shipped on cycle 1 (`make check-full` 34/34 suites ok, `red-first` red on every node, zero blocking findings).
- Non-blocking minor follow-ups noted by cold graders:
  - `core.1`: `parse_semver_tag "v 0.2.0"` trims after `v`; `parse_rendered_release_tag` extracts first `(...)` after `<!-- GENERATED from skills/`.
  - `lint.1`: `scripts/check-bump` could anchor frontmatter start at `NR == 1`.
  - `cli.1`: `do_publish_only` switched to literal `git for-each-ref refs/tags/<tag>` in `sync.1`; `previous_tag`/`bump` remain `null` in `--publish-only` JSON.
  - `sync.1`: `default_self_install` runs `make -C root release` so self-mode release should run from the synced `master` checkout (or use `--no-install` + `make release && make install`).
  - `skills.1`: `skills/warden/SKILL.md:104` parenthetical `(or ./bin/bp3 release <quest> in self mode)` implies `BP3_DECIDER=human` from the outer clause.
- Ready for owner `goal_fin` review (`/warden 2026-11-23-quest-promote-release` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-23-quest-promote-release`).
