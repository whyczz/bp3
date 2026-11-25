---
date: 2026-11-25
quest: ../../QUEST.md
node: draft.1
status: proposed
---

# draft.1 - draft-desk-cli: central `drafts/<slug>` desks, CAS rebase `land --draft`, and `do_remove` `main_root` fix

## TL;DR

Extend `src/quest/layout.ml` and `src/quest/worktree.ml` (building on `2026-11-25-central-desks-dir`) with central draft desks at `<repo_desks_dir>/drafts/<slug>` on branch `draft/<slug>` (`.meta/draft-<slug>.json`, `node = "(draft)"`), implementing `bp3 harness desk prepare --draft <slug>`, `release --draft <slug> [--force]`, and `land --draft <slug> [--target <branch>]`. `land --draft` runs a **3-attempt rebase + atomic CAS fast-forward loop** directly onto `<target>` (never blocked by active quests; cleanly runs `git rebase --abort` and returns `E_MERGE_CONFLICT` on real conflict; deletes the worktree, `.meta/draft-<slug>.json`, and merged `draft/<slug>` branch via `git branch -d`). Add live-derived `target_branch` and `target_dirty` to `bp3 harness desk list`, fix `Worktree.do_remove` to anchor on `main_root ()` so releasing/landing works from inside any linked worktree, add `verb_land`, `e_merge_conflict`, and `e_verify_failed` to `src/quest/names.ml`, update `src/quest/main.ml`, `completions/{_bp3,bp3.bash}`, and `.gitignore` (`*.red-ink.md`, `*.2b-reviewed.md`, `*.2b-reviewed.md.snapshot`), and prove everything in `test/unit/test_layout.ml`, `test/worktree.sh`, and `test/completion.sh`.

## Acceptance gates

Observed today (2026-11-25, `e60eb8a`):

```text
$ ./bin/bp3 harness desk prepare --draft demo
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"worktree prepare needs --run <run-id>"},"guidance":"Fix the call: worktree prepare needs --run <run-id>"}}
$ ./bin/bp3 harness desk land --draft demo
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown worktree verb: land"},"guidance":"Fix the call: unknown worktree verb: land"}}
$ grep -n 'red-ink\.md\|2b-reviewed\.md' .gitignore || echo "0 matches"
0 matches
```

Design trace:

```text
$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk list
{"ok":true,"worktrees":[],"target_branch":"master","target_dirty":false}

$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare --draft icebox-demo
{"ok":true,"run_id":"draft-icebox-demo","quest":"icebox-demo","node":"(draft)","path":"/tmp/d/bp3-<8hex>/drafts/icebox-demo","ref":"draft/icebox-demo","detached":false,"created_ts":...}

# Idempotent second prepare:
$ BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare --draft icebox-demo
{"ok":true,"run_id":"draft-icebox-demo",...,"existing":true}

# Commit a file in the draft desk; master stays 100% clean and unmoved.
# Even if an active quest desk is open AND master moved ahead with a disjoint commit,
# land --draft rebases cleanly, CAS-updates master, syncs clean master checkout, and cleans up —
# even when invoked from inside the draft desk itself:
$ (cd "$draft_path" && BP3_DESKS_DIR=/tmp/d "$repo/bin/bp3" harness desk land --draft icebox-demo)
{"ok":true,"draft":"icebox-demo","branch":"draft/icebox-demo","target":"master","commit":"<sha>","rebased":true,"attempts":1,"landed":true,"released":true,"branch_deleted":true,"conductor_path":"<main_root>"}

# Rebase conflict case: clean `git rebase --abort`, E_MERGE_CONFLICT, draft desk left unconflicted and intact.
$ dune test && ./test/worktree.sh && ./test/completion.sh && make check-full
# rc 0
```

```yaml
objective: implement central draft desks (prepare|release|land --draft <slug> with 3-attempt CAS rebase loop), live target_dirty on desk list, main_root-anchored do_remove, names/completions, and review-scratch .gitignore entries
prove by:
  - test/unit/test_layout.ml: known cases + QCheck2 pairwise non-nesting law across quests/, runs/, and drafts/ + draft_branch formatting
  - test/worktree.sh (with BP3_DESKS_DIR="$work/desks"): prepare/idempotent/list/release/land --draft happy path, rebase-onto-advanced-master + clean master sync, landing succeeds while an active quest desk is open (zero starvation), dirty-draft & dirty-target E_DIRTY_TREE refusals, 0-commits-ahead E_NOT_READY refusal, rebase conflict clean-abort E_MERGE_CONFLICT, CAS contention E_STALE_WORLD on locked master ref, release & land invoked from inside the draft desk itself, and bp3 harness desk parity
  - test/completion.sh: bash and zsh candidates include land under harness desk and worktree
  - grep assertions on .gitignore for *.red-ink.md, *.2b-reviewed.md, *.2b-reviewed.md.snapshot
  - make check && make check-full
done when: all unit, fixture, completion, and full-suite gates pass with zero raw git errors leaked and zero partial ref mutations on failure
```

## Diagram

```text
$BP3_DESKS_DIR (or $HOME/.bp3/desks)
  └── <repo_slug>-<hash8>/
        ├── .meta/
        │     ├── quest-<q>.json
        │     ├── draft-<slug>.json           ◄── NEW (node="(draft)", ref="draft/<slug>")
        │     └── <run_id>.json
        ├── quests/<q>/
        ├── drafts/<slug>/                    ◄── NEW (sibling to quests/ and runs/)
        └── runs/<q>/<node>/<run_id>/

bp3 harness desk land --draft <slug> [--target master]
  │
  ├── 1. load draft-<slug> + inspect clean + on draft/<slug> (E_NOT_FOUND / E_DIRTY_TREE / E_NOT_READY)
  ├── 2. CAS retry loop (attempt = 1..3):
  │        a. read old_target_tip + inspect all target-branch worktrees clean (E_DIRTY_TREE)
  │        b. rev-list --count old_target_tip..draft_tip > 0? (else E_NOT_READY)
  │        c. if not ancestor(old_target_tip, draft_tip):
  │             git -C <draft> rebase <old_target_tip>
  │             on conflict -> git -C <draft> rebase --abort -> E_MERGE_CONFLICT
  │        d. atomic CAS: git update-ref --stdin ("update refs/heads/<target> <new_tip> <old_target_tip>")
  │             on ok -> break; on fail -> retry (after attempt 3 -> E_STALE_WORLD)
  ├── 3. sync clean target worktrees (git -C <wt> reset --hard --quiet HEAD)
  └── 4. git -C <main_root> worktree remove <draft> + delete .meta/draft-<slug>.json
         + git -C <main_root> branch -d draft/<slug>
```

## Pseudocode

```python
# src/quest/layout.ml (pure)
draft_branch_kind = "draft"
def draft_branch(slug: str) -> str:
    return f"draft/{slug}"
def draft_desk_dir(repo_dir: str, slug: str) -> str:
    return f"{repo_dir}/drafts/{slug}"

# src/quest/worktree.ml
def draft_run_id(slug: str) -> str:
    return f"draft-{slug}"

def detect_target_branch(explicit: str | None) -> str | None:
    if explicit:
        return explicit if ref_tip(f"refs/heads/{explicit}") else not_found("branch", explicit)
    if ref_tip("refs/heads/master"): return "master"
    if ref_tip("refs/heads/main"): return "main"
    return None

def target_status(target_opt=None):
    target = detect_target_branch(target_opt)
    wts = [p for (p, b) in worktrees_with_branches() if b == target and file_exists(p)] if target else []
    dirty_wt = next((p for p in wts if inspect_info(p).dirty), None)
    return (target, wts, dirty_wt)

def do_remove(path: str, force: bool):
    info = inspect_info(path)
    if info.dirty and not force:
        err(E_DIRTY_TREE, ...)
    mroot = main_root()
    if canon(mroot) == canon(abs_path(path)):
        err(E_MAIN_WORKTREE, ...)
    run_git_in(mroot, ["worktree", "remove", *(["--force"] if force else []), abs_path(path)])

def do_land_draft(slug: str, target_opt: str | None):
    Store.check_slug(slug)
    rec = load_record(draft_run_id(slug)) or not_found("draft worktree", slug)
    draft_path = abs_path(rec.path)
    if not file_exists(draft_path):
        err(E_NOT_FOUND, ...)
    dinfo = inspect_info(draft_path)
    if dinfo.dirty:
        err(E_DIRTY_TREE, path=rec.path, changed_count=dinfo.changed)
    branch = Layout.draft_branch(slug)
    if dinfo.detached or dinfo.ref != branch:
        err(E_NOT_READY, detail=f"draft desk is on {dinfo.ref}, expected {branch}")

    rebased = False
    landed_tip = None
    attempts = 0
    for attempt in range(1, 4):
        attempts = attempt
        target, target_wts, dirty_wt = target_status(target_opt)
        if not target:
            not_found("branch", target_opt or "master")
        if dirty_wt:
            err(E_DIRTY_TREE, path=dirty_wt)
        old_target = ref_tip(f"refs/heads/{target}")
        draft_tip = ref_tip(f"refs/heads/{branch}")
        if git_rev_list_count(f"{old_target}..{draft_tip}") <= 0:
            err(E_NOT_READY, draft=slug, target=target, commits_ahead=0)
        if not is_ancestor(old_target, draft_tip):
            rc = run_git_in(draft_path, ["rebase", old_target])
            if rc != 0:
                run_git_in(draft_path, ["rebase", "--abort"])
                err(E_MERGE_CONFLICT, draft=slug, target=target)
            draft_tip = ref_tip(f"refs/heads/{branch}")
            rebased = True
        if atomic_cas_ref(f"refs/heads/{target}", new_tip=draft_tip, old_tip=old_target):
            for wt in target_wts:
                run_git_in(wt, ["reset", "--hard", "--quiet", "HEAD"])
            landed_tip = draft_tip
            break
    if not landed_tip:
        err(E_STALE_WORLD, draft=slug, target=target, attempts=attempts)

    do_remove(rec.path, force=False)
    delete_record(rec.run_id)
    mroot = main_root()
    branch_deleted = (run_git_in(mroot, ["branch", "-d", branch]) == 0)
    return {
        "ok": True, "draft": slug, "branch": branch, "target": target,
        "commit": landed_tip, "rebased": rebased, "attempts": attempts,
        "landed": True, "released": True, "branch_deleted": branch_deleted,
        "conductor_path": mroot,
    }
```

## Tables

| Field | Value |
|---|---|
| Intent | add central `drafts/<slug>` desks (`prepare\|release\|land --draft <slug>` with 3-attempt CAS rebase loop), live `target_branch`/`target_dirty` on `desk list`, `main_root`-anchored `do_remove`, `names.ml` constants, completions, and `.gitignore` review-scratch entries |
| Lane | standard |
| Output | `src/quest/layout.ml`, `src/quest/worktree.ml`, `src/quest/names.ml`, `src/quest/main.ml`, `completions/_bp3`, `completions/bp3.bash`, `.gitignore`, `test/unit/test_layout.ml`, `test/worktree.sh`, `test/completion.sh` |
| Acceptance | fails today (`prepare --draft` and `land --draft` return `E_USAGE`, `.gitignore` has 0 review-scratch patterns); passes when all unit, worktree, completion, and full-suite gates pass |
| Depends on | quest `2026-11-25-central-desks-dir` landed on `master` |
| Must not touch | `skills/*`, `.agents/*`, `.claude/*`, `.pi/*`, `AGENTS.md`, `CLAUDE.md`, `CONSTRAINTS.md`, `src/quest/release.ml`, `src/quest/release_io.ml` |

## Prose

Why `land --draft` does **not** block when quest desks are open: under continuous parallel development (5+ quests in flight), blocking drafts whenever any quest desk exists starves drafts permanently. Because `release.1` upgrades `bp3 release` to merge cleanly over concurrent `master` commits via `git merge-tree --write-tree`, drafts can land onto `master` immediately via a 50ms CAS rebase loop so `master` stays fresh for every new session.

Why `do_remove` must anchor on `main_root ()`: `src/quest/worktree.ml:141-144` runs `git rev-parse --show-toplevel` against `root` to detect the main worktree; when a user runs `bp3 harness desk release --draft foo` or `land --draft foo` from inside the draft desk itself, `top_root` equals the draft desk, causing a false `E_MAIN_WORKTREE` refusal. Comparing against `main_root ()` and running `git -C (main_root ()) worktree remove` fixes this cleanly for `draft`, `quest`, `run`, and `exit` desks alike.

Also add `verb_land = "land"` (to `Names.all_verbs`), `e_merge_conflict = "E_MERGE_CONFLICT"`, and `e_verify_failed = "E_VERIFY_FAILED"` to `src/quest/names.ml` in this node so `release.1` reuses them with zero extra `names.ml` churn, and verify `test/unit/test_names.ml` passes (`Store.reserved_slugs` stays synced).

## Tests

- **Known cases (`test/unit/test_layout.ml`):** `draft_branch "icebox-foo" = "draft/icebox-foo"`, `draft_desk_dir "/tmp/d/bp3-12345678" "icebox-demo" = "/tmp/d/bp3-12345678/drafts/icebox-demo"`, and sibling non-overlap between `quests/`, `runs/`, and `drafts/`.
- **Property-based (QCheck2 in `test/unit/test_layout.ml`):** for any valid `(quest, node, run_id, draft_slug)`, `draft_desk_dir`, `quest_desk_dir`, and `run_desk_dir` are pairwise non-nesting (none is equal to or a path-prefix of another).
- **Fixture tests (`test/worktree.sh`, `BP3_DESKS_DIR="$work/desks"`):**
  - `desk list` on clean repo -> `target_branch="master"`, `target_dirty=false`; dirtying `master` -> `target_dirty=true`.
  - `prepare --draft` creates `<desks>/<repo_key>/drafts/<slug>` on `draft/<slug>`, idempotent on repeat (`existing=true`), zero `.bp3/` files in repo.
  - `release --draft` refuses dirty (`E_DIRTY_TREE`), succeeds clean or with `--force`, leaves branch intact, works when invoked from inside the draft desk.
  - `land --draft` happy path (unmoved target -> `rebased=false`, `attempts=1`) and rebased path (disjoint commit on `master` + open active quest desk -> `rebased=true`, `master` worktree synced, draft desk removed, `draft/<slug>` branch deleted).
  - `land --draft` invoked from inside the draft desk itself succeeds and returns `conductor_path = main_root` (no false `E_MAIN_WORKTREE`).
  - `land --draft` refusals: `E_DIRTY_TREE` on dirty draft desk; `E_DIRTY_TREE` on dirty `master` checkout; `E_NOT_READY` on 0 commits ahead; `E_MERGE_CONFLICT` on rebase conflict with clean `rebase --abort` leaving draft desk unconflicted; `E_STALE_WORLD` when `refs/heads/master.lock` blocks all 3 CAS attempts.
- **Completion tests (`test/completion.sh`):** bash and zsh candidate traces assert `land` appears under `bp3 harness desk ""` and `bp3 worktree ""`.
