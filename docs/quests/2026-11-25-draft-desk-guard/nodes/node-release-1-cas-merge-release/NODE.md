---
date: 2026-11-25
quest: ../../QUEST.md
node: release.1
status: proposed
---

# release.1 - cas-merge-release: `git merge-tree` + tiered verification + 2-parent plumbing CAS in `bp3 release`

## TL;DR

Upgrade `src/quest/release.ml` and `src/quest/release_io.ml` so `bp3 release` never forces manual rebases when `master` moved ahead concurrently on disjoint work. Keep strict fast-forward (`strategy: "fast_forward"`) as the zero-overhead fast path when `is_ancestor target_tip source_tip`. When `master` moved ahead (unless `--ff-only` is passed), compute an in-memory 3-way merge (`git merge-tree --write-tree old_target_tip source_tip`, returning `E_MERGE_CONFLICT` with `facts.conflicts` on textual conflict), classify `merge_base..old_target_tip` with pure `Release.classify_drift` (`Doc_only` vs `Code`), run tiered verification in an ephemeral detached worktree at the merged tree (fast `make lint` on `Doc_only`; `BP3_RELEASE_VERIFY_CMD` or `make check-full` on `Code`, returning `E_VERIFY_FAILED` on non-zero exit with `master` untouched and the ephemeral worktree removed), assemble a 2-parent plumbing merge commit (`-p old_target_tip -p source_tip`, preserving every graded node commit SHA in `ledger.jsonl` verbatim) with release files read from the merged tree, and execute an atomic CAS retry loop (max 3 attempts) over `refs/heads/<target>` + `refs/tags/vX.Y.Z`. Add `--ff-only` to completions, unit + QCheck2 tests in `test/unit/test_release.ml`, and full parallel-merge/conflict/verify fixtures in `test/release-door.sh`.

## Acceptance gates

Observed today (2026-11-25, `e60eb8a`):

```text
$ ./bin/bp3 release --help | grep -c -- '--ff-only' || true
0
$ grep -n 'E_NOT_FAST_FORWARD' src/quest/release_io.ml test/release-door.sh
src/quest/release_io.ml:545:      err Names.e_not_fast_forward
test/release-door.sh:163:echo "$out" | jq -e '.error.code == "E_NOT_FAST_FORWARD"' >/dev/null || fail "non-ff code: $out"; ok
```

Design trace:

```text
# Parallel quests q1 and q2 both branch off M0 (disjoint files):
$ BP3_DECIDER=human bp3 release q1
{"ok":true,"tag":"v0.1.0","strategy":"fast_forward","drift_kind":"none","verified_merged":"none","attempts":1,...}

# Dry-run on q2 previews the merge strategy read-only (zero mutations):
$ bp3 release q2 --dry-run
{"ok":true,"dry_run":true,"tag":"v0.2.0","strategy":"merge","drift_kind":"code","conflicts":[],...}

# --ff-only preserves strict E_NOT_FAST_FORWARD when caller explicitly forbids merge commits:
$ BP3_DECIDER=human bp3 release q2 --ff-only
{"ok":false,"error":{"code":"E_NOT_FAST_FORWARD",...}}

# Default CAS release on q2: auto-merges in memory, verifies merged tree, preserves q2 graded SHA as HEAD^2:
$ BP3_DECIDER=human bp3 release q2
{"ok":true,"tag":"v0.2.0","strategy":"merge","drift_kind":"code","verified_merged":"...", "attempts":1,...}
$ git rev-parse master^2   # == exact quest/q2 source_tip (graded SHAs untouched!)

# Doc-only drift on master (e.g. docs/icebox/2026-11-25-note.md) -> drift_kind="doc_only" (fast lint only, skips full code re-check)
# Conflicting lines in same file -> E_MERGE_CONFLICT (facts.conflicts=["shared.txt"]), master untouched
# Failing BP3_RELEASE_VERIFY_CMD on code drift -> E_VERIFY_FAILED, master untouched, ephemeral desk removed

$ dune test && ./test/release-door.sh && ./test/completion.sh && make check-full
# rc 0
```

```yaml
objective: add in-memory git merge-tree --write-tree, pure doc-only vs code drift classification, ephemeral detached-worktree verification, 2-parent plumbing merge commits, 3-attempt CAS retry loop, and --ff-only to bp3 release
prove by:
  - test/unit/test_release.ml: known cases + QCheck2 properties for Release.is_doc_only_path and Release.classify_drift (strict allowlist docs/icebox/, docs/dossiers/, docs/quests/<other>/; rejects .., skills/, src/, test/, Makefile, CONSTRAINTS.md, and docs/quests/<self>/)
  - test/release-door.sh: parallel disjoint q1+q2 auto-merge (HEAD^2 == q2 tip, v0.2.0 tagged, master synced), --dry-run merge preview, --ff-only E_NOT_FAST_FORWARD refusal, doc-only drift skips code verify (BP3_RELEASE_VERIFY_CMD="false" NOT invoked on doc-only drift!), code drift invokes BP3_RELEASE_VERIFY_CMD (passes on true, fails E_VERIFY_FAILED on false with master untouched & 0 leftover ephemeral worktrees), real file conflict fails E_MERGE_CONFLICT with facts.conflicts & master untouched, atomic CAS lock fails E_STALE_WORLD after retries
  - test/completion.sh: --ff-only appears in bp3 release completions (bash + zsh)
  - make check && make check-full
done when: all unit, release-door, completion, and full-suite gates pass cleanly with zero rewritten graded SHAs and zero leftover ephemeral worktrees
```

## Diagram

```text
bp3 release <quest | --commit sha> [--ff-only]
  │
  └── CAS retry loop (attempt = 1..3):
        ├── read old_target_tip; check root + target_wts clean (E_DIRTY_TREE)
        ├── is_ancestor(old_target_tip, source_tip)?
        │     ├── YES ──> strategy = "fast_forward", drift = None_drift
        │     │           base_tree = tree(source_tip), parents = [source_tip]
        │     └── NO  ──> if --ff-only -> E_NOT_FAST_FORWARD
        │                 git merge-tree --write-tree old_target_tip source_tip
        │                   ├── conflicted -> E_MERGE_CONFLICT (facts.conflicts)
        │                   └── clean merged_tree:
        │                         drift = classify_drift(quest, diff(merge_base, old_target_tip))
        │                         verify merged_tree in ephemeral detached worktree (if not dry_run):
        │                           - Doc_only -> make lint (if Makefile has lint:), else skip
        │                           - Code     -> BP3_RELEASE_VERIFY_CMD | make check-full (if present) | skip
        │                           - on fail  -> remove ephemeral worktree -> E_VERIFY_FAILED
        │                         strategy = "merge"
        │                         base_tree = merged_tree, parents = [old_target_tip; source_tip]
        ├── read QUEST.md / gitx.ml / VERSION from base_tree; compute release_files
        ├── new_tip = plumbing_commit(base_tree, parents, release_files, msg)
        ├── tag_obj = plumbing_mktag(new_tip, tag, notes)
        └── atomic_cas_update(target, old_target_tip -> new_tip, create tag)
              ├── ok   -> sync_clean_worktrees(target_wts) -> ledger promote -> gh push -> install
              └── race -> invalidate_ref_caches () -> retry (after 3 -> E_STALE_WORLD)
```

## Pseudocode

```python
# src/quest/release.ml (pure, zero I/O)
type drift_kind = None_drift | Doc_only | Code

def has_dotdot_segment(path: str) -> bool:
    return any(seg == ".." or seg == "." or seg == "" for seg in path.split("/"))

def is_doc_only_path(quest_opt: str | None, path: str) -> bool:
    if has_dotdot_segment(path):
        return False
    if path.startswith("docs/icebox/") or path.startswith("docs/dossiers/"):
        return True
    if path.startswith("docs/quests/"):
        rest = path.removeprefix("docs/quests/")
        slug = rest.split("/", 1)[0]
        if slug == "" or (quest_opt is not None and slug == quest_opt):
            return False  # changes to releasing quest's own folder are NOT doc-only drift
        return True
    return False

def classify_drift(quest_opt: str | None, drifted_files: list[str]) -> drift_kind:
    if not drifted_files:
        return Doc_only
    return Doc_only if all(is_doc_only_path(quest_opt, f) for f in drifted_files) else Code

# src/quest/release_io.ml
def git_merge_tree(ours: str, theirs: str) -> tuple[str, list[str]]:
    # git merge-tree --write-tree --name-only ours theirs
    # exit 0 -> first line is tree SHA; exit 1 -> conflicted paths follow blank line / CONFLICT lines
    ...

def verify_merged_tree(merged_tree: str, drift: drift_kind) -> str:
    # Determine verify command:
    #   Doc_only:
    #     if Makefile in merged_tree has "\nlint:" or starts with "lint:" -> ("lint", ["make", "lint"])
    #     else -> ("skipped_no_gate", None)
    #   Code:
    #     if env BP3_RELEASE_VERIFY_CMD non-empty -> ("custom", ["sh", "-c", cmd])
    #     elif repo_mode() == "self" or Makefile in merged_tree has "check-full:" -> ("full", ["make", "check-full"])
    #     else -> ("skipped_no_gate", None)
    if cmd is None:
        return label
    # Create temporary commit pointing at merged_tree (no ref!), checkout detached worktree under
    # <repo_desks_dir>/runs/_release-verify/<pid>-<attempt>, run cmd, ALWAYS cleanup worktree in Fun.protect.
    # On non-zero rc -> err(E_VERIFY_FAILED, detail=stderr_or_stdout).
    return label

def plumbing_commit(base_tree: str, parents: list[str], files: list[tuple[str, str]], msg: str) -> str:
    # git read-tree <base_tree> into temp GIT_INDEX_FILE
    # hash-object + update-index for each (path, content) in files
    # tree = git write-tree
    # git commit-tree <tree> -p <p1> [-p <p2> ...] < msg
    ...
```

## Tables

| Field | Value |
|---|---|
| Intent | upgrade `bp3 release` with in-memory `git merge-tree --write-tree`, pure `classify_drift`, ephemeral detached-worktree verification, 2-parent plumbing merge commits, 3-attempt CAS retry loop, and `--ff-only` |
| Lane | high-blast-radius |
| Output | `src/quest/release.ml`, `src/quest/release_io.ml`, `completions/_bp3`, `completions/bp3.bash`, `test/unit/test_release.ml`, `test/release-door.sh`, `test/completion.sh` |
| Acceptance | fails today (`--ff-only` absent, parallel disjoint `q2` fails `E_NOT_FAST_FORWARD`); passes when parallel disjoint release auto-merges + verifies, conflicts fail `E_MERGE_CONFLICT`, bad verify fails `E_VERIFY_FAILED`, `--ff-only` fails `E_NOT_FAST_FORWARD`, and all tests pass |
| Depends on | `draft.1 - draft-desk-cli` (uses `names.ml` constants `e_merge_conflict`, `e_verify_failed`, and `Worktree` central desks + `main_root ()`) |
| Must not touch | `skills/*`, `.agents/*`, `.claude/*`, `.pi/*`, `AGENTS.md`, `CLAUDE.md`, `CONSTRAINTS.md`, `src/quest/layout.ml`, `src/quest/worktree.ml` |

## Prose

Why recompute `prev_sv` / `next_sv` / `tag_opt` **inside** the CAS retry loop: if another quest promotes `v0.5.0` between attempt 1 and attempt 2, attempt 2 MUST re-read `list_v_tags ()` so it bumps cleanly to `v0.6.0` instead of colliding on `refs/tags/v0.5.0`! Re-reading `target_tip` and `list_v_tags ()` at the top of each attempt makes concurrent releases truly composable.

Why `plumbing_commit` takes `~base_tree` and `~parents` (instead of a single `~base_tip`): for the fast-forward path (`parents = [source_tip]`) with `files = []`, we still reuse `source_tip` directly with zero extra commit (preserving exact current behavior!). For the merge path (`parents = [old_target_tip; source_tip]`), we **always** create the 2-parent merge commit (even if `files = []`, e.g., `--bump none` with already-landed `QUEST.md`), reading `QUEST.md` / `src/quest/gitx.ml` / `VERSION` from `merged_tree` so concurrent bumps on `master` are never clobbered.

Why `is_doc_only_path` excludes `docs/quests/<this_quest>/` and excludes `skills/`, `AGENTS.md`, `CONSTRAINTS.md`, `Makefile`, `plans/`:
- `test/skills.sh`, `scripts/check-constraints`, and `scripts/check-gates` assert invariants over `skills/`, `AGENTS.md`, `CONSTRAINTS.md`, and `Makefile` — changes there can break tests!
- Only `docs/icebox/**`, `docs/dossiers/**`, and `docs/quests/<other_quest>/**` are genuinely orthogonal to the releasing quest's code and tests; even then, running fast `make lint` (~1s, covering `check-bump` and `check-constraints`) guards against malformed quest frontmatter.

Why ephemeral verification worktrees live under `<repo_desks_dir>/runs/_release-verify/<pid>-<attempt>` and are cleaned up via `Fun.protect`: they never touch `<repo>/.bp3/`, never dirty `master`, and are guaranteed to be removed (`git -C <main_root> worktree remove --force`) whether verification passes, fails, or raises.

## Tests

- **Known cases (`test/unit/test_release.ml`):** `is_doc_only_path` accepts `docs/icebox/2026-11-25-foo.md`, `docs/dossiers/notes.md`, `docs/quests/other-q/QUEST.md`; rejects `docs/quests/my-q/QUEST.md` (when `quest = Some "my-q"`), `src/quest/main.ml`, `skills/quest/SKILL.md`, `AGENTS.md`, `CONSTRAINTS.md`, `Makefile`, `docs/icebox/../src/x.ml`, `""`; `classify_drift` returns `Doc_only` iff all paths are doc-only, else `Code`.
- **Property-based (QCheck2 in `test/unit/test_release.ml`):**
  - `law_non_docs_prefix_never_doc_only`: any generated path not starting with `"docs/"` returns `false`.
  - `law_dotdot_never_doc_only`: any path containing `".."` segment returns `false`.
  - `law_classify_drift_monotonic`: adding any non-doc-only path to any doc-only list always yields `Code`.
- **Fixture tests (`test/release-door.sh`):**
  - Update Section 5 (parallel `q1` + `q2` off `M0` with disjoint files):
    - `q2 --dry-run` previews `strategy: "merge"`, `drift_kind: "code"`, `conflicts: []`.
    - `q2 --ff-only` refuses `E_NOT_FAST_FORWARD`.
    - `q2` (default) auto-merges cleanly, preserves `q2` tip as `master^2`, verifies via `BP3_RELEASE_VERIFY_CMD`, syncs clean `master`, and tags `v0.2.0`!
  - Doc-only drift fixture: commit `docs/icebox/2026-11-25-side.md` onto `master` while `q3` is branched off `M0`; run `BP3_RELEASE_VERIFY_CMD="false" bp3 release q3` -> succeeds with `strategy: "merge"`, `drift_kind: "doc_only"` (proving code-verify command was NOT invoked for doc-only drift!).
  - Code-drift verify failure fixture: commit `src/other.txt` onto `master`, run `BP3_RELEASE_VERIFY_CMD="false" bp3 release q4` -> fails `E_VERIFY_FAILED`, `master` unchanged, zero leftover worktrees in `git worktree list`.
  - Merge conflict fixture: both `master` and `q5` edit `README.md` conflictingly -> fails `E_MERGE_CONFLICT` with `README.md` in `error.facts.conflicts`, `master` unchanged.
  - Atomic CAS lock fixture (`refs/tags/vX.Y.Z.lock`) -> retries 3 times and fails `E_STALE_WORLD` with `master` unchanged.
- **Completion tests (`test/completion.sh`):** `--ff-only` appears in `bp3 release ""` candidates in bash and zsh.
