# verify notes — node-landing-1-landing-wrapup c1

Fresh-run verification of bound commit 71b87fa (handoff run 20261118T144757Z).

- Scorecard: live rollup returns 18 nodes; scorecard.md covers all 18 with
  evidence or named unmeasured (14 wall_null pre-rename nodes, reason stated).
- Disposition: grep -c "^| D" disposition.md = 12; each fixed row names its
  fix step, iceboxed/rejected rows name homes. 100% dispositioned.
- Walkthrough: ./bin/bp3 e returned source_rung=session live; walkthrough.md
  quotes executed rollup/diagram/node-read outputs from the handoff run.
- Diagrams: bp3 g <graph> diagram generated from live state in this run.
- Adherence: bound commit contains only the 4 handoff artifacts; zero tracked
  modifications (git diff empty). git status shows one untracked sibling run
  folder (145437Z-node notes.md) — in-flight system evidence, not a hand-edit.
  Ledger lives in the bp3 store (no ledger.jsonl on disk); rollup setup[]
  confirms the handoff line with run_id 20261118T144757Z stamped.

Verdict: pass.
