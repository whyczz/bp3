# Notes — exp-backtest-1-muse c2

- Fixed the c1 needs_fix defect: `extract_shas` in `src/quest/harness.ml` used OCaml `Str.regexp "[0-9a-f]\{40\}"`; `Str` has no `{n}` repetition, so it never matched and all 2001 c1 traces had empty `commits`. Replaced with a manual bounded scan: exactly 40 lowercase hex chars, not preceded/followed by a hex char, deduped, capped at 20.
- Added the missing fixture assertion in `test/harness.sh`: the good backtest tape must yield `commits == ["0123456789abcdef0123456789abcdef01234567"]` and the refused tape `commits == []`. An unasserted extracted field can stay silently empty while counts stay green.
- Re-ran the corpus replay: 2015 tapes, 1866 identifiable, 729 findings, 925 traces now carry commits (was 0). See `findings.md` / `backtest.json` in this run.
- Verified: `make check` passes (all suites, including the new commits assertions).
- Lesson: in OCaml, reach for a hand scan over `Str` repetition syntax; and assert every extracted trace field at least once.
