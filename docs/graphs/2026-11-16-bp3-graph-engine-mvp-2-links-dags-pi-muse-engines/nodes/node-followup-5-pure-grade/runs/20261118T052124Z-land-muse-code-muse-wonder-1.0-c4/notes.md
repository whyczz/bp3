# Land run notes (cycle 4, commit 691547e)

- Landed from `approved` at cycle 4. Grade c4: ship; verify c4: pass; audit c4: all 14 acceptance rows pass (pure audit, single cast, safe replay, three pushbacks, fix-ledger live, audit-reuse x3, mechanical/disagreement, live mechanical cycle).
- Bound commit 691547e4653d7d708903b1aa05284ecd889d09e9: cached/batch ledger reads + harness-narrowed tape scan; full `make check` author-verified exit 0 at this commit.
- No code changes in this land run; only this run folder's evidence. Untracked c4 node/grade/verify run notes pre-date this run and are left as deliberate evidence.
- Lesson: land needs no re-verification when grade+verify already ran fresh at the bound commit; the single-cast invariant means land is the one remaining cast.
