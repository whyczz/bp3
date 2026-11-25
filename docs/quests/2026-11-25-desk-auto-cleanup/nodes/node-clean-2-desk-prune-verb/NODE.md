---
date: 2026-11-25
quest: ../../QUEST.md
node: clean.2
status: active
---

# clean.2 - desk-prune-verb: add `bp3 harness desk prune [--dry-run]` (+ completions and empty legacy `.bp3/` sweep)

## TL;DR

Add `bp3 harness desk prune [--dry-run]` (and alias `bp3 worktree prune [--dry-run]`, `Names.verb_prune = "prune"`) to sweep dead `missing: true` desk records, clean desks of terminal (`landed`/`canceled`/`deleted`) or merged-into-target quests, merged local `quest/<q>` branches, `git worktree prune`, and empty stub directories under `<repo_desks_dir>` and legacy `<main_root>/.bp3/`. Wire `prune` into `bin/bp3` usage and zsh/bash completions, and prove all safety invariants in `test/worktree.sh` and `test/completion.sh`.

## Acceptance gates

Observed today (2026-11-25, `2ca58e09`):

```text
$ ./bin/bp3 harness desk prune
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown worktree verb: prune"},"guidance":"Fix the call: unknown worktree verb: prune"}}
$ rg -n '\bprune\b' completions/_bp3 completions/bp3.bash bin/bp3 src/quest/names.ml
# 0 matches
```

Design trace:

```text
# Planted repo:
#   - MISSING1 (missing: true record in .meta/ or legacy .bp3/desks/)
#   - quest-landedq (clean desk, QUEST.md status: landed or ledger landed)
#   - quest-mergedq (clean desk, quest/mergedq branch tip already ancestor of master)
#   - quest-activeq (clean desk, unmerged commits, status: active -> MUST KEEP)
#   - quest-dirtyq  (dirty desk, even if landed -> MUST KEEP)
#   - empty stub dirs under <repo_desks_dir>/runs/old/n1 and legacy .bp3/worktrees/old
$ bp3 harness desk prune --dry-run
{"ok":true,"dry_run":true,"released":["MISSING1","quest-landedq","quest-mergedq"],"kept":[{"run_id":"quest-activeq","path":"...","reason":"active"},{"run_id":"quest-dirtyq","path":"...","reason":"dirty"}],"deleted_branches":["quest/landedq","quest/mergedq"],"pruned_dirs":[...]}
# Nothing modified on disk during --dry-run!
$ bp3 harness desk prune
{"ok":true,"dry_run":false,"released":["MISSING1","quest-landedq","quest-mergedq"],"kept":[...],"deleted_branches":["quest/landedq","quest/mergedq"],"pruned_dirs":[...]}
# MISSING1, quest-landedq, quest-mergedq, merged branches, and empty stub dirs gone; quest-activeq and quest-dirtyq untouched.
$ ./test/worktree.sh && ./test/completion.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: implement deterministic bp3 harness desk prune [--dry-run] sweeping missing records, clean terminal/merged desks, merged quest branches, git worktree prune, and empty stub dirs while preserving dirty and active desks
prove by:
  - test/worktree.sh: tests --dry-run read-only plan, real prune removing missing + clean landed + clean merged desks + merged branches + empty central & legacy .bp3/ stub dirs, while keeping dirty and active/unmerged desks untouched, plus bp3 harness desk prune parity and unknown-flag E_USAGE refusal
  - test/completion.sh: tab completion for `bp3 harness desk ` and `bp3 worktree ` includes `prune`
  - make check && make check-full (25/25 suites)
done when: desk prune safely cleans dead/landed/merged desks and empty dirs, never deletes dirty or active work, completions advertise prune, and all 25 suites pass
```

## Diagram

```text
bp3 harness desk prune [--dry-run]
  ├── 1. scan Worktree.load_records() (central .meta/ + legacy .bp3/desks/)
  │        ├── missing on disk         ──► delete_record -> released
  │        ├── dirty worktree          ──► KEEP (reason: "dirty")
  │        ├── clean + terminal quest  ──► release_record -> released
  │        │   (landed|canceled|deleted
  │        │    OR branch merged into master/main)
  │        └── clean + active/unmerged ──► KEEP (reason: "active")
  ├── 2. delete merged, unused local quest/<q> branches (git branch -d only!)
  ├── 3. git -C main_root worktree prune (unless --dry-run)
  └── 4. remove empty leaf dirs under <repo_desks_dir>/{quests,runs,drafts}
         and empty legacy <main_root>/.bp3/{desks,worktrees} (and .bp3 if empty)
```

## Pseudocode

```python
def quest_is_terminal(quest: str, target: str) -> bool:
    # 1. Ledger truth (bp3/quest/<q>)
    qfold = Store.fold_quest(quest)
    if qfold and qfold.state in ("landed", "deleted"):
        return True
    # 2. QUEST.md frontmatter on target branch (or main_root)
    qmd = git_show("refs/heads/" + target, f"docs/quests/{quest}/QUEST.md") or read_file(f"{main_root()}/docs/quests/{quest}/QUEST.md")
    if frontmatter_status(qmd) in ("landed", "canceled"):
        return True
    return False

def desk_branch_merged(r: record, target: str) -> bool:
    if r.r_detached:
        return False
    if r.r_ref == target:
        return False
    return ref_tip("refs/heads/" + r.r_ref) is not None and is_ancestor("refs/heads/" + r.r_ref, "refs/heads/" + target)

def do_prune(dry_run: bool):
    target = detect_target_branch()  # "master" then "main"
    released, kept, candidate_branches = [], [], set()
    for r in load_records():
        if not exists(abs_path(r.r_path)):
            if not dry_run:
                delete_record(r.r_run)
            released.append(r.r_run)
            if r.r_quest:
                candidate_branches.add(Layout.work_branch(r.r_quest))
        else:
            info = try_inspect_info(r.r_path)
            if info and info.idirty:
                kept.append({"run_id": r.r_run, "path": r.r_path, "reason": "dirty"})
            elif quest_is_terminal(r.r_quest, target) or desk_branch_merged(r, target):
                if not dry_run:
                    release_record(r, force=False)
                released.append(r.r_run)
                if r.r_quest:
                    candidate_branches.add(Layout.work_branch(r.r_quest))
            else:
                kept.append({"run_id": r.r_run, "path": r.r_path, "reason": "active"})
    deleted_branches = []
    for br in sorted(candidate_branches):
        if delete_merged_branch(br, target, dry_run):
            deleted_branches.append(br)
    if not dry_run:
        git_in(main_root(), ["worktree", "prune"])
    pruned_dirs = prune_empty_trees(repo_desks_dir(), legacy_bp3_dir(), dry_run)
    return {"ok": True, "dry_run": dry_run, "released": released, "kept": kept,
            "deleted_branches": deleted_branches, "pruned_dirs": pruned_dirs}
```

## Tables

| Field | Value |
|---|---|
| Intent | provide a single safe `bp3 harness desk prune [--dry-run]` command for cleaning stale/missing/landed desks, merged branches, and empty stub dirs |
| Lane | standard |
| Output | `src/quest/names.ml`, `src/quest/worktree.ml`, `bin/bp3`, `completions/_bp3`, `completions/bp3.bash`, `test/worktree.sh`, `test/completion.sh` |
| Acceptance | fails today (`unknown worktree verb: prune`); passes when `test/worktree.sh`, `test/completion.sh`, and `make check-full` pass |
| Depends on | `clean.1 - release-auto-cleanup` |
| Must not touch | `skills/*`, `CONSTRAINTS.md`, `scripts/agy-statusline` |

## Prose

Safety rule for detached grade desks (`r.r_detached = true`): a detached grade desk on an *active* quest is NOT merged-branch-eligible (its `r_ref` is a commit SHA, not a branch), so `desk_branch_merged` returns `false` and `prune` keeps an open grade desk for an active quest unless its quest is terminal (`landed`/`canceled`/`deleted`) or its directory is `missing`. That prevents `desk prune` from ever ripping a grade desk out from under a running cold grader!

Also note on `--dry-run` with `delete_merged_branch`: if a clean terminal desk is in `released` during `--dry-run`, its branch is currently still checked out on disk during `--dry-run`, so preview eligibility should exclude desks already scheduled in `released` when checking `checked_out_branches ()`!

## Tests

- **Fixture tests (`test/worktree.sh`):**
  1. `--dry-run` returns exact `released`, `kept` (`dirty`, `active`), `deleted_branches`, and `pruned_dirs` with zero disk changes.
  2. Real `bp3 harness desk prune` deletes missing records, clean landed/merged desks, merged `quest/<q>` branches, and empty stub dirs (both central and legacy `.bp3/`), while keeping dirty desks, active quest desks, and active grade desks untouched.
  3. Unknown flag (e.g. `prune --bogus`) refused with `E_USAGE`.
- **Completion tests (`test/completion.sh`):** assert `_bp3_candidates harness desk ""` and `_bp3_candidates worktree ""` include `prune`.
