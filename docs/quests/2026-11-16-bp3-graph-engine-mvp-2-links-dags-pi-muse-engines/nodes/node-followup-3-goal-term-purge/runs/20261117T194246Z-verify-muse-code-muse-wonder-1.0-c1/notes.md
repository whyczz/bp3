# Verify notes — node-followup-3-goal-term-purge @ bd58f824

Fresh checks (this run, not claimed green):
- git status --porcelain: FAIL — ` M .../runs/20261117T184210Z-handoff-...-c2/tape.log`, `?? .bp3-context.json`, plus untracked run folders. Dirty handoff tree.
- No handoff ledger line / env run-id stamp found (no ledger.jsonl at node path); fresh conduct read now reports node `blocked` with reason "gated adherence fails: dirty handoff tree, no handoff ledger line or run-id stamp; rename checks pass".
- make check: PASS fresh — `make-exit:0`, 22 "tests: ok" groups, ends install tests: ok.
- ./bin/bp3 skills check: PASS — {"ok":true,"fresh":["node-loop","bp3g-grade","bp3g-land","bp3g-node"]}.
- git grep -i -w quest at bound commit (src/ bin/ scripts/ extensions/ skills/): only exempted hits — migration script rename table, naming legacy-fold note, src/graph/store.ml legacy fold.
- Conduct read (bp3 g r): returned ok, zero rename-caused refusals; node bound to bd58f824.

Verdict: fail — gated adherence rows fail despite rename checks passing. Lesson: a green rename does not cure a dirty, unstamped handoff; adherence is gated.
