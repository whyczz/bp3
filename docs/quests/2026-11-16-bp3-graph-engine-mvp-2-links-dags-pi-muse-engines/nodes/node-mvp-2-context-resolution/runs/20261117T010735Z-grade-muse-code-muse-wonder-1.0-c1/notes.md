# grade run notes — exp-mvp-2-context-resolution (cycle 1)

- Reviewed bound commit 63d49cd by code-reviewer procedure (correctness, design, tests, comments) against EXPERIMENT.md acceptance.
- Claims checked: session>desk resolution, claimed run-id stamping on verdicts+ledger, bare `bp3 e` context print, W_CONTEXT_UNCLAIMED, W_CONTEXT_ENV_MISMATCH (claim wins), ambiguous desk E_NO_CONTEXT with live_run_ids, no sibling inheritance, env-set run-id ruling.
- Ran: dune build --root=. (green), ./test/context.sh (ok), ./test/q.sh (ok), ./test/link.sh (ok), shellcheck on new/changed shell (clean).
- Minor non-blocking findings: (1) the `.bp3-context.json` fallback in resolve_desk is unreachable while the at_desk scan precedes it (same desk_matches gate); (2) `bp3 e` writes bypass guard_write's version-ahead check, consistent with other non-q doors. Neither gates an acceptance case.
- Verdict: ship.
