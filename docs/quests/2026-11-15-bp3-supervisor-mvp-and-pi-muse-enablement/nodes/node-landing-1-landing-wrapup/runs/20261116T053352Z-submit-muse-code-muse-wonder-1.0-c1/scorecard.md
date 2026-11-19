# landing.1 — scorecard (observed)

Quest: `2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement`
Run: `20261116T053352Z-submit-muse-code-muse-wonder-1.0-c1`
Source ledger: `./bin/bp3 q 2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement r`
(verbatim in this run's `tape.log`). Every number below names its source
artifact; nothing is copied from prose about a run.

## Verdict in one line

Before: children narrated their own completion and a shared registry
witnessed them. After: the supervisor folds tapes + pid evidence into
`init / active / finished / orphaned`, the ledger (`bp3 q`) owns
experiment state, and the grader climbs the five-rung evidence ladder.
17 of 18 exps are `landed` / `exp_fin`; this exp closes the record.

## Scorecard — every exp, evidence or unmeasured

| Exp | State (ledger) | Bound commit | Observed evidence |
|---|---|---|---|
| exp-mvp-1-supervisor-cli | landed, cycle 2 | `4fc0cc4de375d13393f85be87e358aebfbeb47c3` | `bp3 harness` door + tick/exit semantics; `test/q.sh`, `src/quest/{main,render,store}.ml` in bound diff |
| exp-mvp-2-find-tape | landed, cycle 2 | `d4d8aff1305f52ae44b91161ab6f6b30290d3cb0` | InitRecord-first `find-tape` with `--entry` pointer resolution; observed live in this run (see walkthrough) |
| exp-mvp-3-watch-run | landed, cycle 1 | `bff373ff1288a5a8250762cd0c25393738bf3092` | blocking `watch`, sole TERM/KILL owner; `src/quest/harness.ml`, `test/harness.sh` |
| exp-mvp-4-supervisor-mechanism | landed, cycle 1 | `fc45070012e83880eea526dee0bb6cf51aa7c288` | induct drives via supervisor; derivation logs are the read path |
| exp-mvp-5-delete-redundant | landed, cycle 1 | `3b8cb47e67ae74a47f351adc0a70922a0cf057e3` | shared-map witness deleted after shadow parity; `run-lifecycle-derivations` sole store |
| exp-mvp-6-harness-desk-api | landed, cycle 1 | `b5897cda3e1892d59317915b1293ac87cfa35417` | nine desk verbs + aliases; `test/{harness,worktree,completion}.sh` |
| exp-mvp-7-grader-evidence-ladder | landed, cycle 1 | `cc1b6866197f8e1d101a07dad88afc5cff537e4d` | ladder wired into `induct-grade`; `test/induct-grade.test.mjs` |
| exp-mvp-8-muse-initrecord-writer | landed, cycle 1 | `a770bd616ed31d9644345a38c55675845a90df85` | launcher `record-init` before spawn (RC1 closed); `test/harness.sh` |
| exp-followup-1-derivation-concurrency | landed, cycle 1 | `8ea4500056d28a59b8b92dee97fcd91ea2381942` | single-`write()` O_APPEND rows + temp+rename cache (RC2) |
| exp-followup-2-finish-evidence | landed, cycle 2 | `135b15c6723a6b9ae4c4005b874aca16ba5983d9` | per-harness finish evidence proved on corpora (RC3); tail-scoped |
| exp-followup-3-tape-binding | landed, cycle 1 | `34afadb3d977e96d3e29fb99aac3eec6490d4d51` | post-spawn `bind-tape` + tail scan skipping `task` entries |
| exp-followup-4-bind-resolution | landed, cycle 2 | `5b23b7033858044bca4b2646b75f832b17e1901f` | own engine-fsm-edge start-order resolution; `E_AMBIGUOUS` on tie |
| exp-backtest-1-muse | landed, cycle 2 | `b6d70067d646f006ea27a6b5b656080a93d4137f` | 2015 tapes, 1866 identifiable, 729 findings, 925 traces with commits — `runs/20261116T001428Z-...-c2/{backtest.json,findings.md}` |
| exp-backtest-2-pi | landed, cycle 1 | `156a6097f7b86f2fc89f0d31ad746135a358de19` | 38 tapes, 43 findings, 33 with finish evidence — `runs/20261116T003423Z-...-c1/{backtest.json,findings.md}` |
| exp-dogfood-1-muse-toy-quest | landed, cycle 6 | `52e5641b3b9d124f3c4fe06954d66a0d425c3ebf` | three.js `flappy.html` in c6 run folder; `node --check` exit 0 (run `notes.md`) |
| exp-dogfood-2-pi-supervisor-rethink | landed, cycle 2 | `dd752a5dbc303b660027122861df23cb49438ecf` | decided design record (owner-approved); keep/replace/drop table in `EXPERIMENT.md` |
| exp-dogfood-3-pi-toy-quest | landed, cycle 1 | `dd930db58d32f54401f1b9fac0ead8367e678111` | pi child `20261116T050354Z-demo-pi-gpt-6.1-sol-c1` derived `finished`; `pi-derivation.json` in c1 run folder |
| exp-landing-1-landing-wrapup | this Run (submit) | this commit | this folder: `scorecard.md`, `disposition.md`, `walkthrough.md`, `notes.md`, `tape.log` |

Supervisor-trace check (this Run, observed): `git rev-parse
--git-common-dir` → `/Users/whycz/m/bp3/.git`; the shared
`bp3/run-lifecycle-derivations/` store holds per-Run `.jsonl` + `.json`
pairs for the quest's Runs (listing in `tape.log`). No scorecard field
lacks a source: ledger, bound diffs, run artifacts, or the traces above.

## Named unmeasured exceptions (capped, with reasons)

| Field | Status | Reason |
|---|---|---|
| Flappy page visually opened in a browser | unmeasured | dogfood.1/.3 verified statically (`node --check` on the extracted module, exit 0); no browser was opened in those Runs, and this Run does not re-open one. A grader may confirm visually. |
| Pi tape source on this host | blind (observed) | `init-check --engine pi` returned `present:false` + `W_SUPERVISOR_BLIND`: the probed source `/Users/whycz/.pi/sessions` is absent while dogfood.3's tape lives under `/Users/whycz/.pi/agent/sessions`. Warn-only by design; lifecycle still derives from pid + InitRecord. Home: disposition D7. |
| Full `supervisor` loop re-run at landing | unmeasured | Landing ran the read-only verbs (`init-check`, `find-tape`, ledger) live; re-driving the acting loop is the owner's `quest_fin` walkthrough, for which `walkthrough.md` is the runnable input. |

## Acceptance mapping

| Case | Result |
|---|---|
| scorecard: every field present or `unmeasured` | met — table above; only the three named exceptions are unmeasured |
| findings: 100% dispositioned with homes | met — `disposition.md` covers all 729 + 43 findings by evidence bucket, each with a home |
| demo inputs: walkthrough runnable from the record | met — `walkthrough.md` was executed in this Run; outputs quoted verbatim |
| env-set run-id | met by mechanism — `BP3_RUN_ID` arrived via environment; the submit verdict/ledger line for this Run carries the stamp (grader evidence) |
