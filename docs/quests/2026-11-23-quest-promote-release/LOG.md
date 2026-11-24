# 2026-11-23-quest-promote-release — Run Log

## Nodes

| Node | State | Cycles | Commit | Notes |
|---|---|---|---|---|
| `node-core-1-release-engine` | todo | 0 | - | pure OCaml `src/quest/release.ml` + `test/unit/test_release.ml` |
| `node-lint-1-bump-lint-and-docs` | todo | 0 | - | `scripts/check-bump` + `RELEASING.md` + unpin `0.2.0`/`0.3.0` tests |
| `node-cli-1-release-door` | todo | 0 | - | top-level `bp3 release` (`<quest>` & `--commit`) + atomic CAS + `CONSTRAINTS.md` |
| `node-sync-1-tag-gated-local-sync` | todo | 0 | - | tag-gated `$PREFIX` install + `share/bp3/RELEASE` + host `SessionStart` auto-sync |
| `node-skills-1-release-skills` | todo | 0 | - | update `quest`, `warden`, `using-bp3` skills + renders + `test/skills.sh` |

## Build notes

- Activated `2026-11-23` under `/induct-inline-yolo` (owner-approved frame + `CONSTRAINTS.md` surface sign-off for `bp3 release`).
