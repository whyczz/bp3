# backtest.2 (pi) — findings report

Findings machine, not a gate: nothing here must pass; everything must be legible.

- corpus: `/Users/whycz/.pi/agent/sessions` (the pi tape source)
- tapes replayed: 38
- identifiable sessions (pi `session` header): 38
- findings: 43
- traces with finish evidence (final assistant `stop` or `session_closed`): 33
- usage validated: fold sums match independent `jq` sums on 3 sampled tapes (15239, 18484, 0 total tokens)
- replay deterministic: two runs byte-identical

## Incident match by name (five known incidents)

The canceled quest's ledger names incidents by exp/run, but pi tapes are keyed by session-id and carry no `BP3_RUN_ID` binding, so exact run-id match is 0/5 — that gap is itself finding F1. Pattern match over the corpus:

| Incident | Pattern | Count |
|---|---|---|
| c3 settled | finish evidence present | 33 |
| c1 unwitnessed | header + messages, no finish, no refusal | 3 |
| c2 fossil (submitted, then silent) | `submit` present, no finish evidence | 0 (9 tapes mention submit; all finished) |
| 2b refusals (x2) | `E_*` refusal with no submit | 40 findings over 12 tapes — see caveat |
| 2a unsettleable | settle attempted, never finished | 0 distinguishable from c1 in tape text alone |

Caveat: most `E_*` strings in pi tapes occur inside the injected system-prompt/skills text, not in dispatcher output, so the refusal count is an upper bound, not ledger truth. No `E_BINDING_REFUSED` occurs in this corpus.

## Findings by proposed fix target

- adapter: 3 (`pi session with no finish evidence`)
- dispatcher: 40 (`E_* refusal with no submit`, upper bound per caveat)

## Pi WAL quirks (adapter gaps, with evidence)

- F1 (adapter/contract): pi tapes bind sessions, never Runs — no `BP3_RUN_ID` in any of the 38 tapes; Run association exists only via an InitRecord written elsewhere. Fix target: contract (dispatcher must record-init before spawn).
- F2 (adapter): no tape uses `session_closed`; every clean end is a final assistant entry with `stopReason: stop`. The fold already treats that as finish evidence (`tape_evidence`, followup.2).
- F3 (adapter): 3 sessions end with neither finish evidence nor a refusal — indistinguishable c1/c2/2a without pid or ledger evidence.
- F4 (adapter): usage is present on assistant entries corpus-wide (`usage_missing` 0 on all real tapes); fold totals equal tape sums on samples.

Full machine-readable replay: `backtest.json` in this run folder (traces + findings). Every finding above is named for dogfood.2's keep/replace/drop table to consume; none gates.
