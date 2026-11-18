# grade — node-followup-3-goal-term-purge c2

Bound commit: 7382b940a14c1bec6e5d1655fb5ef32aeb9fe10a
Run: 20261117T215524Z-grade-muse-code-muse-wonder-1.0-c2
Reviewer procedure: code-reviewer (correctness, design, tests, comments).

## Verdict: fix_first -> needs_fix

Two gated acceptance rows fail at rung 2 on the bound commit itself;
per grade rule any gated fail = needs_fix. Cycle-3 hygiene fix is
otherwise sound.

Findings (severity order):
1. [major] files renamed fails — GRAPH.md record link still points at
   `experiments/exp-followup-3-goal-term-purge/NODE.md`; that path does
   not exist (no `experiments/` dir), so a record points at a broken
   path, violating "no path a record points at is broken".
   Fix shape: re-point to `nodes/node-followup-3-goal-term-purge/NODE.md`.
2. [major] terms synced fails — AGENTS.md Layout still documents
   `GOAL.md` (and "Status is a frontmatter field in GOAL.md"); post
   scope-C the record is `GRAPH.md`. AGENTS.md was never synced.
   Fix shape: rename GOAL.md -> GRAPH.md in AGENTS.md Layout/status text.

What passed (rungs 2-3, run not read):
- Cycle-3 fix itself: .gitignore residue rules, bp3/node probe rename
  (both sites + prompt refs), regression tests in test/ (bp3g-grade
  asserts probe scheme; cleanliness.sh asserts porcelain stays empty).
- grep proof: scoped `grep -riw quest` exits 1 (zero hits) outside the
  named exemptions (store.ml fold, migration table, naming note).
- migration script dry-run completes idempotent; conduct read returns
  handed_off at the bound commit with zero rename-caused refusals.

Lessons:
- A rename is not done while its own index (GRAPH.md) and the repo
  guide (AGENTS.md) still spell the old names; grep-zero scoped to
  code/skills cannot see prose surfaces — include them in the sweep.
- Zero whole-tape reads were needed; rungs 1-3 decided this grade.
