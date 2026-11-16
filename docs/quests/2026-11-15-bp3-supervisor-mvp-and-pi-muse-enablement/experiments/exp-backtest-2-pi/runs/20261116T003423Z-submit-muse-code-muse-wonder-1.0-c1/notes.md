# Notes — exp-backtest-2-pi c1

- Extended `bp3 harness backtest` with `--engine muse-code|pi` (default `muse-code`, so backtest.1 callers are unchanged). Pi traces add `session_id`, `has_header`, `entries`, and summed `usage_input/output/total` plus `usage_missing`; pi findings target `dispatcher`/`adapter`, muse targets unchanged.
- Committed fixtures in `test/harness.sh` cover the Pi parser rows: clean stop, `session_closed`, refusal, header-only, torn tail, foreign JSONL, usage sums, deterministic rerun, and bad-engine `E_USAGE`.
- Real corpus: 38 pi tapes, 38 identifiable, 33 finished, 43 findings. Usage fold matched independent `jq` sums on 3 sampled tapes; two replays were byte-identical.
- Lesson: pi tapes cannot witness Runs — zero carry a `BP3_RUN_ID` binding, so incident truth by run-id is ungradeable from tapes alone; the InitRecord (dispatcher-written) is the only bridge. Also, raw `E_*` text search overcounts refusals because prompts embed error names; treat it as an upper bound.
- Verified: `make check` passes in full, including the new pi backtest assertions. Not run: any live pi drive (out of scope; dogfood.3 owns it).
