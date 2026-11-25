---
date: 2026-11-25
quest: ../../QUEST.md
node: clean.1
status: active
---

# clean.1 - release-auto-cleanup: auto-release quest desks & merged `quest/<q>` branch on `bp3 release` + prune empty parent dirs

## TL;DR

Wire automatic, non-destructive quest cleanup into the tail of `bp3 release <quest>` (`src/quest/release_io.ml`) and add bounded empty-parent pruning (`prune_empty_parents`) to `Worktree.release_record` / `do_remove` (`src/quest/worktree.ml`). Clean or missing desks for the released quest are released automatically, empty parent directories are removed up to `<repo_desks_dir>`, and the merged local `quest/<q>` branch is deleted via `git branch -d` — while any dirty desk is preserved untouched with `W_DESK_DIRTY_KEPT`. `--dry-run` previews the exact cleanup plan read-only.

## Acceptance gates

Observed today (2026-11-25, `2ca58e09`):

```text
$ rg -n "released_desks|kept_desks|branch_deleted" src/quest/release_io.ml
# 0 matches
$ rg -n "prune_empty_parents|delete_merged_branch" src/quest/worktree.ml
# 0 matches
```

Design trace:

```text
# 1. Happy path (including invoking bp3 release from INSIDE the quest desk):
$ BP3_DECIDER=human bp3 release demoq --no-gh --no-install
{"ok":true,"mode":"quest","quest":"demoq",...,"released_desks":["grade-n1-c1-a1","quest-demoq"],"kept_desks":[],"branch_deleted":true,...}
# Both desks removed, empty runs/demoq/n1 & runs/demoq & quests dirs pruned, refs/heads/quest/demoq gone.

# 2. Dirty desk preserved (release still succeeds!):
$ BP3_DECIDER=human bp3 release dirtyq --no-gh --no-install
{"ok":true,"mode":"quest","quest":"dirtyq",...,"released_desks":[],"kept_desks":[{"run_id":"quest-dirtyq","path":"...","reason":"dirty"}],"branch_deleted":false,"warnings":["W_DESK_DIRTY_KEPT"],...}
# Dirty desk and its uncommitted file remain intact on disk; quest/dirtyq branch kept because worktree still holds it.

# 3. --dry-run previews strictly read-only:
$ bp3 release demoq --dry-run
{"ok":true,...,"dry_run":true,"released_desks":["quest-demoq"],"kept_desks":[],"branch_deleted":true,...}
# Desk and branch untouched on disk.

$ ./test/release-door.sh && ./test/worktree.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: auto-release clean/missing quest desks, remove empty parent stub dirs, and delete merged local quest/<q> branch at the tail of bp3 release without ever force-removing dirty desks
prove by:
  - test/unit/test_layout.ml (or test/unit/test_release.ml): pure checks for cleanup plan classification and empty-parent boundary stopping
  - test/release-door.sh: (a) clean quest + grade desk auto-released on bp3 release (including when invoked from inside the quest desk), empty parent dirs removed, local quest/<q> branch deleted; (b) dirty desk kept intact with kept_desks + W_DESK_DIRTY_KEPT and release still exits 0; (c) --dry-run previews released_desks/kept_desks/branch_deleted with zero mutations
  - test/worktree.sh: releasing a run desk under runs/<q>/<n>/<r> removes empty parent dirs up to <repo_desks_dir> without deleting sibling desks
  - make check && make check-full (25/25 suites)
done when: bp3 release cleans up clean/missing desks and merged quest/<q> branches automatically, preserves dirty desks safely, prunes empty parent dirs on every desk release, and all 25 suites pass
```

## Diagram

```text
bp3 release <quest>
  1. validate + CAS update target + sync target worktrees
  2. append ledger promote line
  3. optional gh push/release + optional self $PREFIX install
  4. post-release cleanup (fail-safe; runs last via git -C main_root):
       for r in Worktree.load_records() where r.r_quest == quest:
         ├── missing on disk  ──► delete_record(r)  ──► released_desks += r.r_run
         ├── clean worktree   ──► release_record(r, force=false)
         │                        + prune_empty_parents(r.r_path, stop_at=repo_desks_dir)
         │                        ──► released_desks += r.r_run
         └── dirty worktree   ──► KEEP intact       ──► kept_desks += {r, "dirty"}
                                                        warnings += "W_DESK_DIRTY_KEPT"
       if refs/heads/quest/<q> exists
          and is_ancestor(quest/<q>, target)
          and not checked_out(quest/<q>):
         git -C main_root branch -d quest/<q>  ──► branch_deleted = true
```

## Pseudocode

```python
# src/quest/worktree.ml
def prune_empty_parents(path: str, stop_at: str) -> list[str]:
    removed = []
    cur = dirname(canon_or_self(abs_path(path)))
    stop = canon_or_self(stop_at)
    while cur and cur != stop and cur.startswith(stop + "/"):
        try:
            os.rmdir(cur)
            removed.append(cur)
            cur = dirname(cur)
        except OSError:
            break  # non-empty or missing -> stop
    return removed

def delete_merged_branch(branch: str, target: str, dry_run: bool) -> bool:
    if not ref_tip("refs/heads/" + branch):
        return False
    if branch in checked_out_branches():
        return False
    if not git_in_ok(main_root(), ["merge-base", "--is-ancestor", "refs/heads/" + branch, "refs/heads/" + target]):
        return False
    if dry_run:
        return True
    return git_in_ok(main_root(), ["branch", "-d", branch])

def cleanup_quest(quest: str, target: str, dry_run: bool):
    released, kept, warnings = [], [], []
    for r in [x for x in load_records() if x.r_quest == quest]:
        abs_p = abs_path(r.r_path)
        if not exists(abs_p):
            if not dry_run:
                delete_record(r.r_run)
            released.append(r.r_run)
        else:
            info = try_inspect_info(r.r_path)
            if info and info.idirty:
                kept.append({"run_id": r.r_run, "path": r.r_path, "reason": "dirty"})
                if "W_DESK_DIRTY_KEPT" not in warnings:
                    warnings.append("W_DESK_DIRTY_KEPT")
            else:
                if dry_run:
                    released.append(r.r_run)
                else:
                    try:
                        release_record(r, force=False)  # calls prune_empty_parents
                        released.append(r.r_run)
                    except Exception:
                        kept.append({"run_id": r.r_run, "path": r.r_path, "reason": "cleanup_failed"})
                        if "W_DESK_CLEANUP_FAILED" not in warnings:
                            warnings.append("W_DESK_CLEANUP_FAILED")
    branch_deleted = delete_merged_branch(Layout.work_branch(quest), target, dry_run)
    return (released, kept, branch_deleted, warnings)
```

## Tables

| Field | Value |
|---|---|
| Intent | make `bp3 release <quest>` automatically release clean/missing desks, remove empty parent dirs, and delete merged local `quest/<q>` branches safely |
| Lane | standard |
| Output | `src/quest/worktree.ml`, `src/quest/release_io.ml`, `test/release-door.sh`, `test/worktree.sh` |
| Acceptance | fails today (`release_io.ml` emits no `released_desks`/`kept_desks`/`branch_deleted` and leaves desks + branches behind; `worktree.ml` leaves empty parent dirs); passes when all unit + fixture checks and `make check-full` pass |
| Depends on | none |
| Must not touch | `skills/*`, `CONSTRAINTS.md`, `completions/*`, `scripts/agy-statusline` |

## Prose

Why cleanup runs at the very tail of `Release_io.run`: if the owner invokes `BP3_DECIDER=human $DESK/bin/bp3 release <q>` from inside the quest desk, running `atomic_cas_update`, `sync_clean_worktrees`, `append_quest_promote_line`, `push_and_create_gh_release`, and `self_install_hook` first ensures every release artifact is already published and installed from `install_root` (`master`) before `$DESK` is unlinked via `git -C main_root worktree remove`.

Note on `--commit <sha>` releases (no quest): `released_desks` is `[]`, `kept_desks` is `[]`, `branch_deleted` is `false` — zero unexpected desk touches on non-quest patch releases.

Note on `--dry-run` `branch_deleted`: in `--dry-run`, if `refs/heads/quest/<q>` is currently checked out ONLY by desks in `released` (which would be released before `branch -d` runs), report `branch_deleted: true` when `is_ancestor (work_branch q) target` or when `source_tip` is `quest/<q>` (which the release itself is about to promote onto `target`!). That way `--dry-run` accurately previews what the real release will do!

## Tests

- **Fixture tests (`test/release-door.sh`):**
  1. Quest release with open clean quest desk + clean grade desk (invoked from inside the quest desk) -> `released_desks` contains both, `kept_desks == []`, `branch_deleted == true`, both paths and empty parent dirs gone, `git show-ref --verify refs/heads/quest/<q>` fails.
  2. Quest release with a dirty quest desk -> exits 0, `kept_desks` lists the dirty desk (`reason: "dirty"`), `warnings` contains `"W_DESK_DIRTY_KEPT"`, `branch_deleted == false`, uncommitted file intact on disk.
  3. `--dry-run` previews `released_desks`, `kept_desks`, and `branch_deleted` while leaving desks and branches untouched.
- **Fixture tests (`test/worktree.sh`):** releasing `runs/demo/node-a/R1` prunes empty `runs/demo/node-a` and `runs/demo` without touching sibling `runs/demo2/...` or `<repo_desks_dir>`.
