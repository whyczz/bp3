# followup.7 author run — notes

- Root cause was one line: `resolveRepoRoot` returned
  `dirname(gitCommonDir(cwd))`, the main checkout. Fix:
  resolve via `git rev-parse --show-toplevel` (new
  `gitTopLevel` helper beside `gitCommonDir`, same typed
  `E_NOT_FOUND` refusal). Name reuses the repo's word:
  `resolveRepoRoot` unchanged; bp3's OCaml side already
  uses `--show-toplevel` for work roots.
- Shared state deliberately untouched: `derivationsDir`
  and pi-sessions still resolve via the common dir, so
  Run derivations stay in one shared store.
- `--show-toplevel` returns the canonical (realpath'd)
  path; the old common-dir path could return the
  caller's spelling. Two test assertions now compare
  against `fs.realpathSync(...)` — same contract,
  canonical spelling (macOS `/private` tmp prefix).
- Evidence: repro before fix (worktree and nested
  resolved to main) and after (all OK); suite 12/12;
  `make check` green; unpinned drive from this quest
  worktree (nested cwd, `BP3_PI_BP3_BIN` unset)
  derived `finished`, derivation log in the shared
  common-dir store. Toy drive artifacts removed after.
