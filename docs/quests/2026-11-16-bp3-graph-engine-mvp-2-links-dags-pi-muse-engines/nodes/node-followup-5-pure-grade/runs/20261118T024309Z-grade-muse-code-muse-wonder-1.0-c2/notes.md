# Grade notes — node-followup-5-pure-grade cycle 2 (bound 31b7c74)

Verdict: needs_fix (mechanical), failed row: regression.

Lessons:
- The dogfood-parallel combined-cast fix itself (apply dispatch before bp3link_
  parse; single grade cast with verify_verdict) reads correct and its named
  test passes per handoff notes; the grade turns on a different gated row.
- Regression row requires `make check` green. At the bound commit,
  test/completion.sh fails: src/graph/main.ml parses --verify-verdict and
  --mechanical (since 4ab3228) but completions/_bp3 and completions/bp3.bash
  omit both. Verified by flag-parity extraction at 31b7c74 (MISSING both).
- The RESOLVED claim of "make check exit 0" at the handoff commit was asserted
  before the gate finished; NODE.md's own correction admits it. Trust the
  parity check over commit-message claims.
- Fix is named/mechanical: add both flags to both completion lists (as the
  follow-up 0ee41e2 does); no owner judgment needed, never blocks.
