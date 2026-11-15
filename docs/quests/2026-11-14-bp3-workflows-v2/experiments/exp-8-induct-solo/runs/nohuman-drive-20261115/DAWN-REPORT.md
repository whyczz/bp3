# Dawn report — live no-human drive (conductor-run, 2026-11-15)

Queue: `2026-11-15-toy-nohuman-clean`,
`2026-11-15-toy-solo-park`,
`2026-11-15-toy-solo-clean`.

| Quest | Result | Evidence |
|---|---|---|
| toy-nohuman-clean | exp-1-hello `exp_fin` (todo->submitted->approved->landed, separate dispatches) | `bp3 q r` rollup landed; commit `c4f2f6d4` |
| toy-solo-park | PARKED in inbox — "seeded park: owner must name the file; no autonomous choice", cycle 1, checkpoint `dfea4e76` | `bp3 q r` inbox, quoted verbatim |
| toy-solo-clean | PARKED (blocked c1) — submit hit `E_DIRTY_TREE` from the conductor's own mid-drive edits; graded fail on the adherence row | inbox reason: "gated fail: submit edge E_DIRTY_TREE" |

Tokens (usage_recorded sums, `.git/bp3-run-registry.json`,
clean quest's three dispatches): 19,067,581 input /
229,842 output, 37 LLM calls, 4 registered Runs.
Worktree sweep after the drive:
`{"ok":true,"worktrees":[]}`.

Budget row (first queue): the queue was budget-capped
at 3 quests by the conductor; all 3 were processed
(2 parked, 1 finished) — no budget stop occurred there;
the cap and its accounting are stated here, not
inferred.

Budget stop, observed (second queue, 2026-11-15):
queue `[2026-11-15-toy-budget-stop]`, stated budget
1 Run. Exactly one Run was dispatched
(`20261115T031513Z-submit-muse-code-muse-wonder-1.0-c1`;
registry: 3,959,182 input / 48,420 output tokens,
10 LLM calls) and it submitted `exp-1-hello`
(commit `2ce75003`). After that Run the budget was
spent, so no review, check, or land step was
dispatched: `bp3 q r 2026-11-15-toy-budget-stop`
shows the exp still `submitted`, `fin: null`. The
queue stopped mid-quest because the budget stopped
it — stated from the dispatch count, not inferred.

Lessons: a dirty tree from the operator's own edits is
a park, not a pass; the seeded decision parked without
any attestation attempt; nothing promoted or pushed.
