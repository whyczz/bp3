# Land run notes — exp-mvp-1-link-claim

- Claimed the one-time harness link successfully; returned run_id `20261117T004025Z-land-muse-code-muse-wonder-1.0-c1` as expected.
- Verified the concrete run folder did not pre-exist before creating it, avoiding any overwrite/reuse collision.
- Kept all subsequent shell output teed to `tape.log` as verbatim evidence; tape text is not parsed into facts.
- Invoked the `land` state edge directly via `bp3 q u` with BP3_RUN_ID/BP3_QUEST/BP3_EXP/BP3_HARNESS/BP3_MODEL set, per the child contract.
- Lesson: always check the exact run-folder path under the quest worktree first — the conductor checkout is a different location — and capture the claim output before proceeding.
