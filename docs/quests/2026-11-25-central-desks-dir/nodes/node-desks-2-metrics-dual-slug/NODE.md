---
date: 2026-11-25
quest: ../../QUEST.md
node: desks.2
status: active
---

# desks.2 - metrics-dual-slug: discover Claude and pi transcripts from both central desks and legacy `.bp3/worktrees/`

## TL;DR

Update `src/quest/metrics_io.ml` (`default_dirs` for Claude Code `~/.claude/projects/` and `default_pi_dirs` for pi `~/.pi/agent/sessions/`) so transcript discovery matches sessions run in: (1) `main_root`, (2) this repo's central desk bucket `<desks_base>/<repo_key>/...` (both logical and `realpath` spellings), and (3) legacy `<main_root>/.bp3/worktrees/...` (preserving historical quest scrapes), while excluding sibling repos and other repos' central desk buckets. Prove all cases in `test/metrics.sh`.

## Acceptance gates

Observed today (2026-11-25, `c8bfbb9`):

```text
$ rg -n "desks_root" src/quest/metrics_io.ml
61:  let desk_tail = "-" ^ slug_of_path Layout.desks_root ^ "-" in
83:      let desk = pi_slug (r ^ "/" ^ Layout.desks_root ^ "/") in
```

Design trace:

```text
# Claude Code (~/.claude/projects/):
#   matches:  <slug(main_root)>
#             <slug(desks_base/repo_key)>-*          (new central desks)
#             <slug(main_root)>--bp3-worktrees-*     (legacy desks)
#   excludes: <slug(main_root)>-sibling
#             <slug(desks_base/other-repo-12345678)>-*
# pi (~/.pi/agent/sessions/):
#   matches:  --<pi(main_root)>--
#             --<pi(desks_base/repo_key)>-*--        (new central desks)
#             --<pi(main_root)>-.bp3-worktrees-*--   (legacy desks)
#   excludes: --<pi(main_root)>-sibling--
#             --<pi(desks_base/other-repo-12345678)>-*--
$ ./test/metrics.sh && make check-full
# rc 0 (25/25 suites)
```

```yaml
objective: scan Claude Code and pi transcript directories for both central $BP3_DESKS_DIR/<repo_key>/ desks and legacy <main_root>/.bp3/worktrees/ desks without matching other repos
prove by:
  - test/metrics.sh: fixtures planting main_root, central $BP3_DESKS_DIR/<repo_key>/quests/q1, central $BP3_DESKS_DIR/<repo_key>/runs/q1/n1/r1, legacy .bp3/worktrees/q1, sibling repo, and another repo's central bucket ($BP3_DESKS_DIR/other-deadbeef/...) for BOTH Claude (default_dirs) and pi (default_pi_dirs)
  - make check && make check-full (25/25 suites)
done when: default_dirs and default_pi_dirs match main + central + legacy dirs only, exclude other repos' central buckets, and make check-full passes
```

## Diagram

```text
Metrics_io.default_dirs() / default_pi_dirs()
  ├── repo root:    main_root (logical + realpath)
  ├── central root: Worktree.repo_desks_dir () (logical + realpath)  ──► matches quests/* and runs/*
  └── legacy root:  main_root ^ "/" ^ Layout.legacy_desks_root       ──► preserves pre-v0.6.0 scrapes
```

## Pseudocode

```python
def candidate_roots(path: str) -> list[str]:
    real = realpath_or_self(path)
    return sorted_uniq([path, real])

def default_dirs():  # Claude Code ~/.claude/projects/
    mains = [slug_of_path(r) for r in candidate_roots(main_root())]
    central = [slug_of_path(r) + "-" for r in candidate_roots(Worktree.repo_desks_dir())]
    legacy_tail = "-" + slug_of_path(Layout.legacy_desks_root) + "-"
    def ours(d):
        return (
            any(d == m or d.startswith(m + legacy_tail) for m in mains)
            or any(d.startswith(c) for c in central)
        )
    ...

def default_pi_dirs():  # pi ~/.pi/agent/sessions/
    mains = candidate_roots(main_root())
    centrals = candidate_roots(Worktree.repo_desks_dir())
    def prefix_of(p):
        s = pi_slug(p + "/")   # "--...---"
        return s[:-2]          # "--...-"
    def matches_prefix(d, pref):
        return d.startswith(pref) and d.endswith("--") and len(d) > len(pref) + 2
    def ours(d):
        return (
            any(d == pi_slug(r) or matches_prefix(d, prefix_of(r + "/" + Layout.legacy_desks_root)) for r in mains)
            or any(matches_prefix(d, prefix_of(c)) for c in centrals)
        )
    ...
```

## Tables

| Field | Value |
|---|---|
| Intent | keep Claude and pi transcript scraping working across both new central `~/.bp3/desks/` worktrees and historical `.bp3/worktrees/` quests |
| Lane | standard |
| Output | `src/quest/metrics_io.ml`, `test/metrics.sh` |
| Acceptance | fails today (`metrics_io.ml` ignores `~/.bp3/desks/<repo_key>/...` directories); passes when `test/metrics.sh` proves central + legacy + exclusion cases for both Claude and pi and `make check-full` passes |
| Depends on | `desks.1 - central-layout-and-worktree` |
| Must not touch | `Makefile`, `scripts/check-gates`, `skills/*`, `CONSTRAINTS.md`, `src/quest/worktree.ml` (except calling existing helpers exposed in `desks.1`) |

## Prose

Note on `agy` (`default_agy_dirs`): Antigravity stores conversations under `~/.gemini/antigravity-cli/brain/<conv-id>/` (not keyed by cwd slug), so `default_agy_dirs` needs zero changes — only `default_dirs` (Claude Code) and `default_pi_dirs` (pi) filter by cwd-derived project directory slugs.

Edge case: on macOS, `TMPDIR` is `/var/folders/...` whose `Unix.realpath` is `/private/var/folders/...`. Because `BP3_DESKS_DIR` in tests (or symlinked home dirs) can be spelled either logically or physically, matching both `c` and `realpath c` prevents silent misses when Claude or pi records the physical cwd.

## Tests

- **Known cases (`test/metrics.sh`):** export `BP3_DESKS_DIR="$work/desks"`, compute the fixture repo's central bucket path (e.g., via `bp3 harness desk derive`), plant Claude and pi session dirs for: (a) main repo, (b) central quest desk, (c) central run desk, (d) legacy `.bp3/worktrees/` desk, (e) sibling repo, (f) another repo's central bucket (`other-deadbeef`). Assert (a)–(d) are scanned and (e)–(f) are excluded.
- **Property-based:** omitted — directory slug matching over the finite enumerated root shapes above (covered deterministically in `test/metrics.sh`).
