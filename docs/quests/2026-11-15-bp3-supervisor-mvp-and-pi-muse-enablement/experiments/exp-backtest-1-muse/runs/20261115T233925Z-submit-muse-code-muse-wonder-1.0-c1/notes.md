# Notes — exp-backtest-1-muse c1

- Added `bp3 harness backtest [--corpus <dir>]` (alias `b`): replays the muse fold over stored tapes, extracting BP3_RUN_ID bindings, bp3 invocations, E_* refusals, commit shas, and finish/exit evidence per tape. Findings list names tape, run-id, evidence, and fix target (bp3 q u / hooks / adapter). Findings never gate; a parser crash would fail the call.
- Corpus run: 2001 tapes replayed, 1854 identifiable, 720 findings (see findings.md / backtest.json in this run).
- Lesson: the real muse corpus is dominated by foreign/approval-review tapes and Runs with no finish evidence — the fold must stay pointer-only and never treat a bare mention as a binding (tape_references_run discipline reused via extract_run_ids).
- Verified: `make check` passes (harness.sh includes new backtest fixtures: good/refused/torn/foreign tapes, usage and E_NOT_FOUND paths).
