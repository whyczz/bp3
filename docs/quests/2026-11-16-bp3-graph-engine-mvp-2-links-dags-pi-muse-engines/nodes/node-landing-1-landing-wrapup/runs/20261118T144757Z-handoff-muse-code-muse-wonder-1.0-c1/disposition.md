# landing.1 — findings disposition (100%, with homes)

Rule applied: no finding is called `fixed` unless a fix step
implemented it; otherwise it is iceboxed or rejected with a
home. Sources: this graph's node records, run notes, the live
rollup, and GRAPH.md's deliberately-open table — all read in
this Run (tape.log).

| # | Finding | Disposition | Home / fix step |
|---|---|---|---|
| D1 | Grade died on missing evidence; evidence gaps burned an author cycle (config.1 c1 papercut) | fixed | followup.1 grade-evidence + followup.2: audit re-collects internally; gaps never burn a cycle |
| D2 | Dispatch launched a stale workflow render calling retired `record-init` (mvp.1 grade) | fixed | followup.2 workflow-birth: `E_RENDER_STALE` refuses a render older than its source |
| D3 | Container word wrong on live surfaces (`goal` for the DAG container) | fixed | followup.3 scope-C migration (script, dry-run, idempotent); landed c4 `2dbe30ce` |
| D4 | Grader could race its own verdict cast; grade had side effects | fixed | followup.5 pure-grade: grader computes, looper applies one cast; landed c4 `691547e4` |
| D5 | Every cycle paid full `make check` | fixed | followup.6 check-tiers: `check-changed` + `check-fast`; full check stays the gate; landed `f96a9696` |
| D6 | Two same-second `link mint` calls collided on run-id; second mint overwrote the first run config (dogfood.2 c1) | fixed | dogfood.2 itself: `O_EXCL` write + next-second retry in `src/graph/harness.ml`; explicit `--run-id` still refuses `E_EXISTS` |
| D7 | Rollup shows 14 pre-rename nodes `todo` with `wall_s: null` despite observed land runs; `deps: []`, one ready-set wave | iceboxed | Ledger history keeps old words by settled design (GRAPH.md Terms); the fold maps verbs, not node IDs. Re-keying history is the owner's call at promotion. Home: this row + scorecard note (a) |
| D8 | Setup outliers over the 3-minute gate: followup.3 verify c4 `316 s`, dogfood.3 handoff c1 `1963 s` (`W_SETUP_SLOW` on the live rollup) | iceboxed | GRAPH.md timing gate: measure always, optimize only when setup > 3 min. Both are measured and named; no optimization was promised. Home: this row |
| D9 | Session-id exposure: which rung do claims land on? (GRAPH deliberately-open) | fixed (muse arm) | dogfood.1 measured the drives; this Run's `bp3 e` resolved `source_rung: session` live (walkthrough). A third rung is designed only if session+desk fail routinely — not observed |
| D10 | Dep freeze rule undecided (GRAPH deliberately-open) | iceboxed | mvp.3 built deps mutable-but-logged; no anomaly was recorded in dogfood.2. The freeze proposal is the root worker's, at the owner's promotion review. Home: this row + GRAPH.md |
| D11 | Pi extension loading into spawned children (GRAPH deliberately-open) | iceboxed | dogfood.1 proved the Pi tree shape on the dispatcher's session-file fixture; a live Pi session drive remains the Pi arm owner's. Home: dogfood.1 run notes + this row |
| D12 | Tokens per node and human-active minutes have no in-system field | rejected (not a defect) | GRAPH scorecard law: visibility, not caps; fields report `unmeasured`, never zero (scorecard). No number is owed until a meter exists |

Coverage: every finding named in this graph's records, run
notes, rollup warnings, and deliberately-open table appears
above exactly once — 6 fixed (each with its fix step), 4
iceboxed with homes, 1 fixed-in-part (D9), 1 rejected with the
mechanism named. Nothing is "fixed" without a fix step.
