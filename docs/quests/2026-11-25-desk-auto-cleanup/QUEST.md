---
status: landed
home_repo: bp3
date: 2026-11-25
bump: minor
---

# desk-auto-cleanup: auto-release quest desks & merged branches on `bp3 release` and add `bp3 harness desk prune`

TL;DR
Make `bp3 release <quest>` automatically release that quest's clean or missing desks, remove empty parent directories, and delete its merged local `quest/<quest>` branch (never `--force` deleting dirty desks — keeping them with `W_DESK_DIRTY_KEPT`), and add `bp3 harness desk prune [--dry-run]` (alias `bp3 worktree prune`) to sweep stale `missing: true` records, clean landed/canceled/merged desks, and empty desk/legacy `.bp3/` stub directories on demand. Keep `SessionStart` read-only.

ELI5
Right now, after you finish and release a quest, its git worktree desk, metadata JSON, empty folders, and merged `quest/<slug>` branch all sit around until you release them by hand. This quest makes `bp3 release` clean up after itself automatically (while refusing to delete any desk with uncommitted edits) and adds one `bp3 harness desk prune` command to sweep leftover dead desks and stale branches in a single shot.

## Context

Owner direction (2026-11-25):
- Split post-quest cleanup and session-scoped statusline into two independent quests (`2026-11-25-desk-auto-cleanup` and `2026-11-25-session-scoped-statusline`).
- Delete merged local `quest/<slug>` branches once merged into `master` (on `bp3 release` and `desk prune`).
- Keep `SessionStart` read-only; run automated cleanup inside `bp3 release` plus manual `bp3 harness desk prune [--dry-run]`.

Measured ground (audited 2026-11-25 on `master` `2ca58e09`, `v0.6.0`):

| Fact | Source |
|---|---|
| `Release_io.run` ends after `self_install_hook` without releasing any quest desks or deleting merged `quest/<quest>` branches; every promoted quest leaves its desk and branch behind | `src/quest/release_io.ml:663-714` |
| `Worktree.release_record` removes the worktree and unlinks `.meta/<run_id>.json`, but never removes empty parent dirs (`runs/<q>/<n>`, `runs/<q>`, `quests/`) or empty legacy `.bp3/` stubs | `src/quest/worktree.ml:387-398` |
| `Worktree.run` has no `prune` verb (`unknown worktree verb: prune`), and `Names.all_verbs` has no `verb_prune` | `src/quest/worktree.ml:504-537`, `src/quest/names.ml:25-52` |
| `bin/bp3` usage line, `completions/_bp3:138-140`, and `completions/bp3.bash:142-144` list `derive create inspect remove prepare check exit release list` without `prune` | `bin/bp3:423`, `completions/_bp3:137-140`, `completions/bp3.bash:141-144` |
| `Warden_io.post_land_commits_for` already falls back cleanly to `HEAD` when `refs/heads/quest/<q>` has been deleted | `src/warden/warden_io.ml:153-165` |
| On 2026-11-25, 9 stale desks (`quest-2026-11-25-central-desks-dir`, `quest-2026-11-23-codebase-diet`, `quest-2026-11-18-test-pyramid`, and 6 `missing: true` records from Nov 15–23) plus 4 empty Nov 14–15 `.bp3/worktrees/` stub trees had accumulated and required manual cleanup | live `bp3 harness desk list` (2026-11-25) |

## Terms

| Term | Meaning |
|---|---|
| `W_DESK_DIRTY_KEPT` | warning string emitted by `bp3 release` when a desk belonging to the released quest has uncommitted changes (`dirty = true`) and is preserved untouched |
| `released_desks` | JSON array of `run_id` strings released by `bp3 release` (or previewed in `--dry-run`) |
| `kept_desks` | JSON array of `{run_id, path, reason}` objects preserved by `bp3 release` or `desk prune` (never force-removed) |
| `branch_deleted` | bool on `bp3 release` verdict (`true` iff local `quest/<q>` existed, was merged into `target`, had no remaining worktree checked out on it, and was deleted) |
| `verb_prune` | `"prune"` in `src/quest/names.ml` — new subcommand under `bp3 harness desk prune [--dry-run]` (and alias `bp3 worktree prune [--dry-run]`) |
| `terminal quest` | a quest whose `bp3 q` ledger folds to `landed` or `deleted`, OR whose `QUEST.md` frontmatter on `target` has `status: landed` or `status: canceled`, OR whose worktree branch tip is already an ancestor of `target` |
| `prune_empty_parents` | bounded `Unix.rmdir` walk upward from a removed desk directory, stopping at `<repo_desks_dir>` or `<main_root>/.bp3` (never deletes non-empty directories, never deletes outside desk roots) |

## Inputs

| Input | Source & precedence |
|---|---|
| `bp3 release <quest> [--dry-run] ...` | existing release CLI door; automatically runs quest desk & merged-branch cleanup after atomic CAS promote + publish + optional `$PREFIX` install (or previews read-only under `--dry-run`) |
| `bp3 harness desk prune [--dry-run]` | new subcommand (alias `bp3 worktree prune [--dry-run]`); `--dry-run` computes exact JSON plan with zero mutations |
| `BP3_DESKS_DIR` / `HOME` | central desks base directory (from `v0.6.0`); tests isolate via `BP3_DESKS_DIR="$work/desks"` |
| `Worktree.load_records ()` | live list of central `.meta/*.json` + legacy `<main_root>/.bp3/desks/*.json` desk records |

## Outputs

| Output | Shape |
|---|---|
| `bp3 release <quest>` verdict JSON | existing schema **plus** `"released_desks":[<run_id>...]`, `"kept_desks":[{"run_id":...,"path":...,"reason":"dirty"}]`, `"branch_deleted":bool`, and optional `"warnings":["W_DESK_DIRTY_KEPT"]` (same fields previewed in `--dry-run` with zero writes) |
| `bp3 harness desk prune [--dry-run]` verdict JSON | `{"ok":true,"dry_run":bool,"released":[<run_id>...],"kept":[{"run_id":...,"path":...,"reason":"dirty|active|unmerged"}],"deleted_branches":[<branch>...],"pruned_dirs":[<path>...]}` |
| `Worktree.release_record` filesystem side effect | removes empty parent stub dirs (`runs/<q>/<n>`, `runs/<q>`, `quests/`) up to `<repo_desks_dir>` (and empty legacy `.bp3/worktrees/...` parents) |
| `bin/bp3`, `completions/_bp3`, `completions/bp3.bash` | advertise and tab-complete `prune` under `harness desk` / `worktree` |
| `skills/{using-bp3,warden}/SKILL.md` (+ renders) | document automatic post-release cleanup and `bp3 harness desk prune [--dry-run]` |

## Acceptance gates

Observed today (2026-11-25, `master` `2ca58e09`, `v0.6.0`):

```text
$ ./bin/bp3 harness desk prune
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown worktree verb: prune"},"guidance":"Fix the call: unknown worktree verb: prune"}}
$ rg -n "released_desks|branch_deleted" src/quest/release_io.ml
# 0 matches
```

Design trace (after quest lands):

```text
clean.1   # release a goal_fin quest with an open clean quest desk + clean grade desk
          BP3_DECIDER=human bp3 release demoq --no-gh --no-install
            -> {"ok":true,...,"released_desks":["grade-n1-c1-a1","quest-demoq"],"kept_desks":[],"branch_deleted":true,...}
          # both desks gone, empty runs/demoq/n1 & runs/demoq & quests dirs pruned, refs/heads/quest/demoq deleted
          # release with a DIRTY desk: release still succeeds, dirty desk stays intact on disk:
            -> {"ok":true,...,"released_desks":[],"kept_desks":[{"run_id":"quest-demoq","path":"...","reason":"dirty"}],"branch_deleted":false,"warnings":["W_DESK_DIRTY_KEPT"]}
          # --dry-run previews released_desks/kept_desks/branch_deleted without removing anything
          ./test/release-door.sh && make check-full -> rc 0

clean.2   # repo with 1 missing record, 1 clean landed desk, 1 clean active desk, 1 dirty landed desk, and empty stub dirs
          bp3 harness desk prune --dry-run
            -> {"ok":true,"dry_run":true,"released":["OLD_MISSING","quest-landed"],"kept":[{"run_id":"quest-active","reason":"active"},{"run_id":"quest-dirty","reason":"dirty"}],...}
          bp3 harness desk prune
            -> removes OLD_MISSING + quest-landed + merged branch + empty stub dirs; preserves quest-active & quest-dirty
          ./test/worktree.sh && ./test/completion.sh && make check-full -> rc 0

skills.1  # using-bp3 and warden document release auto-cleanup and desk prune; renders fresh
          ./bin/bp3 skills check -> {"ok":true,"fresh":[],...}
          ./test/skills.sh && make check-full -> rc 0
```

## Goal and why

End manual post-quest housekeeping without risking uncommitted work. After `2026-11-25-central-desks-dir` moved desks out of the repo into `~/.bp3/desks/`, forgotten desks and merged `quest/<slug>` branches became out-of-sight clutter. Wiring safe clean/missing cleanup directly into `bp3 release` and adding one deterministic `bp3 harness desk prune` verb eliminates drift while keeping `SessionStart` fast and read-only.

## Success picture

- `bp3 release <quest>` leaves zero clean or missing desks, zero empty parent stub directories, and zero merged local `quest/<quest>` branches behind — while never deleting a dirty desk.
- `bp3 harness desk prune [--dry-run]` sweeps dead records, clean landed/canceled/merged desks, `git worktree prune`, and empty stub directories in one deterministic call.
- `SessionStart` remains strictly read-only with respect to desks and branches.
- `using-bp3`, `warden`, `bin/bp3` usage, and shell completions document the new behavior accurately.

## Scope

| In | Out |
|---|---|
| Auto-release of clean/missing quest desks + merged local `quest/<q>` branch deletion at tail of `bp3 release <quest>` (`clean.1`) | Deleting dirty desks (`--force`) during `bp3 release` or `desk prune` |
| Empty parent dir cleanup (`prune_empty_parents`) on `Worktree.release_record` and `do_remove` (`clean.1`) | Deleting remote branches (`origin/quest/*`) or bp3 state branches (`refs/heads/bp3/*` — ledger truth must never be deleted!) |
| `bp3 harness desk prune [--dry-run]` + `bp3 worktree prune` + completions (`clean.2`) | Auto-running `desk prune` inside `SessionStart` hooks (explicitly kept read-only per owner 2026-11-25) |
| Skill docs in `skills/{using-bp3,warden}/SKILL.md` + renders (`skills.1`) | Session-scoped `agy-statusline` (separate quest `2026-11-25-session-scoped-statusline`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Adds zero languages, zero libraries (OCaml stdlib `Unix`, `Filename`, `Sys` + existing git plumbing), and zero new top-level CLI surfaces (`prune` is a subcommand under existing signed `bp3 harness` / `bp3 worktree`; `bp3 release` is already signed). No edit to `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Q1 Orchestration (`CONTEXT.md:23`, checked 2026-11-19): *"Exact work lives in deterministic scripts and judgment in the agent, and 'the two never mix'."* Moving post-release cleanup from manual agent memory into deterministic OCaml inside `bp3 release` and `desk prune` eliminates forgotten desks permanently.
  - Q2 Storage (`CONTEXT.md:34`, checked 2026-11-19): *"Daemons that sync state draw complaints. bp3: no daemon."* No background GC daemon — cleanup triggers deterministically on `bp3 release` or explicit `bp3 harness desk prune`.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (optional `/red-ink`) | owner |
| Promote & release (`goal_fin`: `/warden` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-desk-auto-cleanup`) | owner |

## Nodes

### Milestone: clean

| Node | TL;DR |
|---|---|
| [clean.1 - release-auto-cleanup](nodes/node-clean-1-release-auto-cleanup/NODE.md) | auto-release clean/missing quest desks & delete merged local `quest/<q>` branch at tail of `bp3 release` (previewed in `--dry-run`, dirty desks kept with `W_DESK_DIRTY_KEPT`), plus `prune_empty_parents` in `worktree.ml` |
| [clean.2 - desk-prune-verb](nodes/node-clean-2-desk-prune-verb/NODE.md) | add `bp3 harness desk prune [--dry-run]` (`Names.verb_prune`), `git worktree prune`, empty central/legacy stub cleanup, `bin/bp3` usage, and zsh/bash completions + `test/worktree.sh` & `test/completion.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - document-auto-cleanup-and-prune](nodes/node-skills-1-document-auto-cleanup-and-prune/NODE.md) | document automatic post-release cleanup and `bp3 harness desk prune [--dry-run]` in `skills/{using-bp3,warden}/SKILL.md`, re-render all harnesses, and lock in `test/skills.sh` |

## Scorecard

| Row | Baseline (2026-11-25, `2ca58e09`) | Target | Read from |
|---|---|---|---|
| clean quest desks left after `bp3 release <q>` | 1+ (never released automatically) | **0** (dirty desks kept with `W_DESK_DIRTY_KEPT`) | `test/release-door.sh` |
| merged local `quest/<q>` branch left after `bp3 release <q>` | 1 (never deleted) | **0** (deleted when merged & unused) | `test/release-door.sh` |
| empty parent dirs left after `desk release` | left behind (`runs/<q>/<n>`, `quests/`) | **0** (pruned up to `<repo_desks_dir>`) | `test/worktree.sh` |
| one-command GC for stale/missing/landed desks | none (`E_USAGE`) | `bp3 harness desk prune [--dry-run]` | `test/worktree.sh`, `test/completion.sh` |

## Risks and red chair

Red chair of the plan AND the source prompt (Step 7.5):

- **Attack 1 (Critical — invoking `bp3 release <q>` from INSIDE the quest desk itself):**
  - During `v0.6.0`, `bp3 release` was invoked via `$DESK/bin/bp3` while `root` was the quest desk. If cleanup ran BEFORE `self_install_hook` or `push_and_create_gh_release`, removing `$DESK` could break later steps that read from `root`.
  - **Settled in `clean.1`:** Run desk + branch cleanup as the **very last step** of `Release_io.run` (after CAS update, `sync_clean_worktrees`, ledger promote line, GitHub push/release, AND `self_install_hook`), running git commands with `-C main_root ()`. Proved in `test/release-door.sh` by invoking `bp3 release <q>` from inside the quest desk itself!
- **Attack 2 (Critical — accidentally deleting a dirty desk or unmerged work during `release` or `prune`):**
  - Deleting an uncommitted edit or an active draft/quest desk would cause irreversible data loss.
  - **Settled in `clean.1` + `clean.2`:** Neither `bp3 release` nor `bp3 harness desk prune` ever passes `--force` to `do_remove`. Any `dirty = true` desk is skipped and reported in `kept_desks` / `kept` with `reason: "dirty"`. Any branch deletion uses `git branch -d` (NEVER `-D`) ONLY after verifying `is_ancestor branch target`. Proved with explicit dirty-desk and unmerged-desk preservation tests in `test/release-door.sh` and `test/worktree.sh`.
- **Attack 3 (Major — `bp3 release` failing because desk cleanup hits an unexpected filesystem error after `master` was already promoted and tagged):**
  - Once `atomic_cas_update` and `gh release create` succeed, a desk-removal hiccup must NEVER crash `bp3 release` with non-zero exit (making the owner think the release failed!).
  - **Settled in `clean.1`:** Wrap post-release desk/branch cleanup in fail-safe error handling: any desk that cannot be removed goes into `kept_desks` with its reason and `W_DESK_CLEANUP_FAILED`, and `bp3 release` still exits 0 with the full release verdict.
- **Attack 4 (Major — deleting `bp3/quest/*` or `bp3/node/*` storage branches during cleanup):**
  - Ledger branches under `refs/heads/bp3/` are permanent audit truth.
  - **Settled in `clean.1` + `clean.2`:** Branch deletion ONLY targets `Layout.work_branch q` (`quest/<q>`) — never `refs/heads/bp3/*`, never `master`/`main`, never `draft/*` unless merged & explicitly cleaned by `draft-desk-guard`.
- **Attack 5 (Minor — interaction with `2026-11-25-draft-desk-guard`):**
  - `draft-desk-guard` adds `<repo_desks_dir>/drafts/<slug>` desks.
  - **Settled in `clean.2`:** `desk prune` checks `<repo_desks_dir>` subdirectories generically (`quests`, `runs`, `drafts` if present) and only releases `draft-*` records when `missing: true` or clean + merged into `target`, so both quests compose cleanly regardless of landing order.

## Open questions

None — all scope and trigger decisions settled by owner on 2026-11-25.

## Node diagram

```text
Wave 1: clean.1 (release-auto-cleanup: Release_io tail cleanup + Worktree.prune_empty_parents
                 + delete_merged_branch + test/release-door.sh)
           │
Wave 2: clean.2 (desk-prune-verb: bp3 harness desk prune [--dry-run] + Names.verb_prune
                 + completions + test/worktree.sh + test/completion.sh)
           │
Wave 3: skills.1 (document-auto-cleanup-and-prune: skills/{using-bp3,warden}/SKILL.md
                  + renders + test/skills.sh)
```
