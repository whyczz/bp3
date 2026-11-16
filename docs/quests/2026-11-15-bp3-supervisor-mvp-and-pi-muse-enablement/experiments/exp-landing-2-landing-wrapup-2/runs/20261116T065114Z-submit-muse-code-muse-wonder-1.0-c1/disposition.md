# landing.2 — findings disposition: the pi-extension arc (100%, with homes)

Rule applied (exp): no finding is called `fixed` unless a
findings-fix step implemented it; otherwise it is iceboxed or
rejected with a home. Landing.1's D1–D9 (backtest.1/.2) stand
unchanged; this table covers only what the pi-extension arc
(followup.5, followup.6, dogfood.4) newly raised.

## Sources (landed, committed)

- followup.5 c1 notes: `exp-followup-5-pi-extension/runs/20261116T060036Z-submit-muse-code-muse-wonder-1.0-c1/notes.md`
- followup.6 c1 notes: `exp-followup-6-pi-dispatcher-complete/runs/20261116T062123Z-submit-muse-code-muse-wonder-1.0-c1/notes.md`
- dogfood.4 c1 notes: `exp-dogfood-4-pi-extension-drive/runs/20261116T063944Z-submit-muse-code-muse-wonder-1.0-c1/notes.md`
- Fresh confirmation in this Run: `node --test extensions/bp3-pi/test/bp3-pi.test.mjs`
  11/11 pass; `./test/harness.sh: all checks passed` (verbatim in
  this folder's `tape.log`).

Every finding the arc raised falls in exactly one row below, so
disposition coverage is 100% by construction.

## Disposition table

| # | Finding (source) | Disposition | Home / evidence |
|---|---|---|---|
| P1 | followup.5 shipped `await_runs` / `release_desk` / roles as thin verbatim relays, completion deferred (followup.5 notes) | fixed | followup.6 landed the completion: thin `await_runs` over `bp3 harness watch` (sole killer), dirty-refusing `release_desk`, `roles/*.md` routing effective `BP3_MODEL` / `BP3_THINKING` (override > role > conductor), `record-init --thinking` in `src/quest/harness.ml`. Fresh in this Run: role-routing, await, and release cases pass (11/11). |
| P2 | Derivation-store resolution: `bp3` resolves its store from `BP3_ROOT` / cwd, so the suite drives the raw binary in a temp repo while production calls go through `bin/bp3`; a first test run polluted the real store via the shim and was cleaned up (followup.5 notes) | rejected (test-harness artifact, not a product defect) | The committed suite isolates its store per test; production resolution through `bin/bp3` is the settled path (QUEST: paths resolve from the git common dir). No product change is owed; the shim behavior stays a suite concern. |
| P3 | InitRecord ordering: `record-init` is called with the live pid right after spawn; real pi writes its tape header after startup, so the InitRecord lands first in practice, but the code guarantees only "live pid named, before observed work" (followup.5 notes) | rejected (honest bound, correctly stated) | followup.4's bind resolution plus followup.6's InitRecord checks pin the order the design needs (`record-init` before exit, `bind-tape` after). The weaker stated guarantee is the true one; no stronger claim is made anywhere in the scorecard. |
| P4 | Real-pi hung/silent drives not run: the hung, silent, and closed-not-exited cases are proved on the fake-pi suite plus the OCaml `watch` suite, not on a hung real pi child (followup.6 notes; followup.6 review concurred) | iceboxed (deliberately open, named exception) | The killer under test (`bp3 harness watch`) is engine-shared OCaml code, exercised by `test/harness.sh` (re-run green in this Run) and the fake-pi drive trace. A real hung-pi drive remains available to the owner as a follow-up; it is recorded as `unmeasured` in the scorecard, not claimed. Home: this row + scorecard exceptions. |
| P5 | Blind pi tape source persists: `init-check --engine pi` probes `/Users/whycz/.pi/sessions`, absent on this host, while real pi tapes live under `/Users/whycz/.pi/agent/sessions`; `find-tape` for a pi Run therefore refuses `E_NOT_FOUND` from this desk (dogfood.4 drive; landing.1 D8; re-observed live in this Run) | iceboxed (deliberately open) | Same home as landing.1 D8: warn-only is the settled design (QUEST: blindness adds no fifth lifecycle word; lifecycle derives from pid + InitRecord). Aligning the probed pi source path is deferred to the owner's next pi pass. The dogfood.4 `finished` derivation is unaffected — it folds from the InitRecord and the bound tape, not from the probed source. Home: this row + QUEST.md blindness rule. |
| P6 | Worktree-shaped roots bite the drive: the dispatcher's repo-root resolution (git common dir's parent) lands on the main checkout in a quest worktree, whose older `bin/bp3` lacks the `harness` door, so dogfood.4 attempt 1's `record-init` refused `E_BP3_FAILED`; the retry pinned `BP3_PI_BP3_BIN` to the worktree's `bin/bp3` and gave the child an absolute artifact path (dogfood.4 notes) | iceboxed (deliberately open) | The extension needed no change; the gap is worktree-shaped roots, named by the author as "worth a follow-up naming". The successful drive (`drive.jsonl`) is the observed product behavior from a normal checkout. A root-resolution fix must open its own exp — none is claimed here. Home: this row + dogfood.4 c1 notes. |

Two smaller observations from the arc carry no defect and need no
row of their own: zombie pids fool `kill(pid, 0)` in the test parent
(followup.6: assert the exit signal instead — a test-writing lesson,
already applied in the suite), and `list_runs` on cache-missing
failure-kind Runs pays watch's 5s fallback per Run (followup.6:
honest latency, not a hang). Both are recorded here so nothing
learned is lost; neither blocks landing.

## What "fixed" claims — and what it does not

Fixed means a landed exp implemented the mechanism (P1, by
followup.6). It does not mean the deferred real-pi hung drive was
run (P4), the probed pi source path was aligned (P5), or
worktree-shaped roots were repaired (P6): those three stay
iceboxed with homes, and the scorecard marks the first two
`unmeasured` rather than borrowing credit.
