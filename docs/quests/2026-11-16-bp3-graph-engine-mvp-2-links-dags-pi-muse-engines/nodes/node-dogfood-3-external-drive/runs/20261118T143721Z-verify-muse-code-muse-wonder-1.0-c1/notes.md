# dogfood.3 external-drive — verify notes (cycle 1)

Verdict: pass on ac43954bd4e746115fc8761b3ce8f2fe95063c68 (fresh, this session).

- mode derives self: ./bin/bp3 config -> mode self.
- no flag surface: skills install --mode host -> derivation usage error, exit 2.
- skill sets: ./test/mode.sh -> mode tests: ok (49 assertions).
- mode-aware reads: skills/bp3g/workflows/node-loop.js:82 bp3Bin desk ternary.
- host/recorded: /tmp/flappy-bird run record mode host, run 20261118T141104Z.
- external conduct: flappy score-counter state landed (21fb9de), smoke ok, zero bp3-source files, tree clean.
- regression: make check exit 0.
- adherence: HEAD == bound commit, tracked diff empty; live porcelain shows only untracked parallel run folders. Node read: handed_off c1, run_id stamped. Ledger is store-backed (no ledger.jsonl file); bp3 read corroborates it.

Lesson: judge tracked diff at the bound commit, not live porcelain — parallel grade/verify run folders pollute porcelain without touching tracked state.
