# landing.2 — scorecard delta: the pi-extension arc (observed)

Quest: `2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement`
Run: `20261116T065114Z-submit-muse-code-muse-wonder-1.0-c1`
Base scorecard: `exp-landing-1-landing-wrapup/runs/20261116T053352Z-submit-muse-code-muse-wonder-1.0-c1/scorecard.md`
(18 exps; unchanged by this delta). Source ledger, read live in this
Run: `./bin/bp3 q 2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement r`
(verbatim in this run's `tape.log`). Every number below names its
source artifact; nothing is copied from prose about a run.

## Verdict in one line

Before landing.1: the pi engine was a hand-played launcher
(dogfood.3). After this arc: a pi conductor with `bp3-pi` loaded
spawns, awaits, and releases real work through exactly four tools
(`spawn_run`, `await_runs`, `list_runs`, `release_desk`), roles route
`BP3_MODEL` / `BP3_THINKING` into the child, `bp3 harness watch`
stays the sole TERM/KILL owner, and the supervisor — never the
extension — folds `finished` / `orphaned`. 22 of 22 quest exps are
now accounted for: 21 `landed` / `exp_fin`, this Run submits the last.

## Diligence gate (runs first, per red-ink-quest-landing-demo)

| Check | Result |
|---|---|
| Design settled | pass — no `EXPERIMENT.red-ink.md` working copy open for followup.5/.6, dogfood.4; dogfood.2's decided design is the adopted input |
| Acceptance met, observed | pass — every Acceptance case for the three arc exps has run evidence (below); fresh re-runs in this Run confirm it |
| Review judged the exp | pass — each arc exp carries audit/check/review runs whose verdict binds its bound commit and its Acceptance cases (run folders listed below) |

No failed exp, so no red-ink detour is owed before this record.

## Scorecard delta — the pi-extension arc, evidence or unmeasured

| Exp | State (ledger) | Bound commit | Observed evidence |
|---|---|---|---|
| exp-followup-5-pi-extension | landed, cycle 1 | `7a92e59c31cb8111ad29c611c105abd4477563df` | `extensions/bp3-pi/` (extension + dispatcher, spawn path); suite 4/4 at landing; fresh re-run in this Run: 11/11 (the suite grew with followup.6) |
| exp-followup-6-pi-dispatcher-complete | landed, cycle 1 | `89f683ea9e3d2ecfb1716b0f2f5ada701c839bff` | `roles/*.md` + `src/roles.ts`, thin `await_runs` over `watch`, dirty-refusing `release_desk`, `record-init --thinking` in `src/quest/harness.ml`; fresh in this Run: 11/11 pass, `harness.sh: all checks passed` |
| exp-dogfood-4-pi-extension-drive | landed, cycle 1 | `18ad6c587d71a4c159a0d186a5ade869dda00b2d` | pi conductor drove `spawn_run` → `await_runs` → `list_runs` (`drive.jsonl`, 425 lines); child Run `20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1` derived `finished` (`pi-derivation.json`, `warnings: []`, `pid_alive: false`); `flappy.html` 8439 bytes, module `node --check` exit 0 (re-run in this Run) |
| exp-landing-2-landing-wrapup-2 | this Run (submit) | this commit | this folder: `scorecard.md`, `disposition.md`, `walkthrough.md`, `notes.md`, `tape.log` |

Quest rollup (live ledger in this Run): 21 exps `landed` / `exp_fin`,
`exp-landing-2-landing-wrapup-2` the only `todo`, quest `state:
proposed`, `rollup: active`. The other 18 exps are unchanged from
the landing.1 scorecard; their bound commits and evidence links
stand as recorded there.

Supervisor-trace check (this Run, observed): `git rev-parse
--git-common-dir` → `/Users/whycz/m/bp3/.git`; the shared
`bp3/run-lifecycle-derivations/` store holds the dogfood.4 child
Run's `.jsonl` + `.json` pair with `lifecycle: finished`. No
scorecard field lacks a source: ledger, bound diffs, run artifacts,
or the fresh runs above.

## Named unmeasured exceptions (capped, with reasons)

| Field | Status | Reason |
|---|---|---|
| Flappy page visually opened in a browser | unmeasured | dogfood.4 verified statically (`node --check` on the extracted 7059-byte module, exit 0, re-run here); no browser was opened in any drive Run, and this Run does not open one. A grader may confirm visually. |
| Pi tape source on this host | blind (observed) | `init-check --engine pi` returned `present:false` + `W_SUPERVISOR_BLIND` again in this Run: the probed source `/Users/whycz/.pi/sessions` is absent while real pi tapes live under `/Users/whycz/.pi/agent/sessions`. Warn-only by design; lifecycle still derives from pid + InitRecord. Home: disposition P5. |
| `find-tape` for the dogfood.4 pi child from this desk | refused, observed | `find-tape --run-id 20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1` returned `E_NOT_FOUND` in this Run (same pi-source path gap as D8 in landing.1). The committed `pi-derivation.json` plus the shared-store `.json` remain the observed `finished` evidence; a muse Run resolves fine (`find-tape` for landing.1's submit Run returned its tape path, observed). |
| Real-pi hung/silent drives | unmeasured | followup.6 proved hung/silent/closed-not-exited on the fake-pi suite plus the OCaml `watch` suite (`harness.sh`, re-run here); no real pi child was hung at landing. The killer under test is engine-shared code, not the child binary. Home: disposition P4. |
| Full `supervisor` loop re-run at landing | unmeasured | Landing ran the read-only verbs (`init-check`, `find-tape`, ledger) live; re-driving the acting loop is the owner's `quest_fin` walkthrough, for which `walkthrough.md` is the runnable input. |

## Acceptance mapping

| Case | Result |
|---|---|
| scorecard: every new exp present with observed evidence or a named `unmeasured` with reason | met — delta table above; only the named exceptions are unmeasured |
| findings: 100% of new findings dispositioned (fixed / iceboxed / rejected, each with a home); nothing called "fixed" without a fix step | met — `disposition.md` covers every finding the arc raised (P1–P6), each with a home |
| walkthrough: run, not merely scheduled; outputs quoted from the run | met — `walkthrough.md` was executed in this Run; outputs quoted verbatim |
| env-set run-id (owner ruling from mvp.1) | met by mechanism — `BP3_RUN_ID` arrived via environment; the submit verdict/ledger line for this Run carries the stamp (grader evidence) |
