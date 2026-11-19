# grade — node-followup-3-goal-term-purge c1

Bound commit: bd58f824c35c001287882dcacf6a3b708f3aa77e
Run: 20261117T194241Z-grade-muse-code-muse-wonder-1.0-c1
Reviewer procedure: code-reviewer (correctness, design, tests, comments).

## Verdict: fix_first -> needs_fix

Functional rename survives review; gated adherence rows fail and block ship.

Findings (severity order):
1. [critical] Gated adherence fails — evidence matrix rows "no hand-edited state",
   "clean commit", "handoff by child", "env run-id stamped" are fail.
   Re-observed at grade time: `git status --porcelain` still shows a modified
   handoff tape.log plus untracked `.bp3-context.json`; cited node-local
   ledger path has no handoff line. Per grade rule any gated fail = needs_fix.
   Fix shape: re-handoff from a clean tree via the claimed child path so the
   handoff ledger line carries the stamped run-id.
2. [minor] Naming skill keeps `goal/<slug>` branch wording while the migration
   moved work branches to `graph/<slug>`; harmless, flagged for a later sync.

What passed (rungs 1-3, run not read):
- files renamed: NODE.md present at bound commit; GRAPH.md live; ids unchanged.
- grep proof: remaining `quest` hits sit only in named exemptions (store.ml
  legacy fold, migrate script rename table, naming fold note, refuse-tests).
- skills check: {"ok":true,"fresh":["node-loop","bp3g-grade","bp3g-land","bp3g-node"]}
- conduct survives: node reads handed_off at the bound commit, grade legal.
- terms synced: naming SKILL.md:35 states goal/graph with docs/graphs path.
- Code: single legacy fold in src/graph/store.ml; comments agree with code;
  tests assert old doors/names refuse (test/g.sh, test/skills.sh).

Lessons:
- A rename can be mechanically perfect and still fail grade on process
  evidence; keep the handoff tree clean and let the edge call stamp the ledger.
- Zero whole-tape reads were needed; rungs 1-3 decided this grade.
