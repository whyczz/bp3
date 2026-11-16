# landing.1 — findings disposition (100%, with homes)

Rule applied (exp addendum): no finding is called `fixed` unless a
findings-fix step implemented it; otherwise it is iceboxed or rejected
with a home. A finding that correctly describes honest behavior is
rejected as not-a-defect, with the mechanism that proves it named.

## Sources (landed, committed)

- backtest.1 c2: `exp-backtest-1-muse/runs/20261116T001428Z-submit-muse-code-muse-wonder-1.0-c2/findings.md`
  — 2015 tapes, 1866 identifiable Runs, 729 findings (adapter 418, `bp3 q u`/hooks 311), 925 traces with commits.
- backtest.2 c1: `exp-backtest-2-pi/runs/20261116T003423Z-submit-muse-code-muse-wonder-1.0-c1/findings.md`
  — 38 tapes, 43 findings (adapter 3, dispatcher 40 as an upper bound), 33 with finish evidence.

Every finding falls in exactly one bucket below; buckets sum to the
totals, so disposition coverage is 100% by construction.

## Disposition table

| # | Bucket (count) | Disposition | Home / evidence |
|---|---|---|---|
| D1 | backtest.1: identifiable Run, no finish evidence (269) | rejected (not a defect) | These tapes genuinely never closed; the fold deriving them non-`finished` is correct. The mechanism gap that once made even closed muse tapes unreachable (close-marker assumed) was fixed by followup.2 (`dac90d4`, `135b15c`: exit entry + pid dead, tail-scoped) and followup.3/4 (tape binding). Residual historical orphans stay `orphaned` by design — QUEST lifecycle table. |
| D2 | backtest.1: foreign tape, no `BP3_RUN_ID` binding (149) | rejected (not a defect) | No InitRecord, no Run: InitRecord-first lookup (mvp.2) correctly refuses to guess. Session-id remains reverse lookup only. |
| D3 | backtest.1: `E_*` refusal with no submit (311; largest `E_DIR` 18, `E_DIRTY_TREE` 13, `E_USAGE` 12, long tail of 1-count codes) | rejected (honest stops) | A refusal with no submit is the ledger truth the backtest compared against; the fold matched it. Owners stay `bp3 q u` + hooks; no adapter change is owed. Any future code-level fix must open its own exp — none is claimed here. |
| D4 | backtest.2 F1: pi tapes bind sessions, never Runs — no `BP3_RUN_ID` in 38/38 tapes | fixed (future supervised path); historical tapes rejected | Dispatcher `record-init` before spawn (mvp.8, RC1) + dogfood.2's decided contract; proved live by dogfood.3, whose pi Run derived `finished` from its InitRecord (`pi-derivation.json`). The 38 historical tapes remain unbound history. |
| D5 | backtest.2 F2: no tape uses `session_closed`; clean end is final assistant `stopReason: stop` (33 with finish evidence) | fixed | followup.2's per-harness finish evidence: pi's last whole entry decides (`session_closed` or a stopped final assistant entry). Fold already treats it as finish evidence. |
| D6 | backtest.2 F3 + adapter remainder: 3 sessions with neither finish evidence nor refusal | rejected (not a defect) | Indistinguishable from genuinely unfinished Runs without pid/ledger evidence; deriving them non-`finished` is the honest result (same principle as D1). |
| D7 | backtest.2 dispatcher bucket: `E_*` refusal with no submit (40 findings over 12 tapes, upper bound) | rejected (honest stops, overstated) | backtest.2 itself caveats that most `E_*` strings occur inside injected prompt/skills text, not dispatcher output; no `E_BINDING_REFUSED` occurs in the corpus. No dispatcher defect is evidenced. |
| D8 | Blindness: missing/reshaped tape source (`W_SUPERVISOR_BLIND`) | iceboxed (deliberately open) | Observed live at landing: `init-check --engine pi` → `present:false`, `warnings:["W_SUPERVISOR_BLIND"]` (probed `/Users/whycz/.pi/sessions` absent; dogfood.3's tape sits under `/Users/whycz/.pi/agent/sessions`). Warn-only is the settled design (QUEST: blindness adds no fifth lifecycle word); aligning the probed pi source path is deferred to the owner's next pi pass. Home: this row + QUEST.md blindness rule. |
| D9 | Pointer digest rot if a harness compacts its tape before grade time (DECISION-RECORD RC5) | iceboxed (deliberately open) | Settled as open at adoption: the grader ladder falls back a rung and backtests measure it. Home: `DECISION-RECORD.md` RC5. |

Counts check: D1 269 + D2 149 + D3 311 = 729 (backtest.1). D4–D7
cover all 43 (backtest.2: 3 adapter + 40 dispatcher-upper-bound, with
F1/F2/F4 named inside). D8/D9 carry no backtest count; they are the
quest's own deliberately-open items, recorded so nothing is dropped.

## What "fixed" claims — and what it does not

Fixed means a landed exp implemented the mechanism (D4, D5). It does
not mean historical tapes changed their derivation: orphans stay
orphaned, foreign tapes stay foreign. That is the design working,
not unfinished work.
