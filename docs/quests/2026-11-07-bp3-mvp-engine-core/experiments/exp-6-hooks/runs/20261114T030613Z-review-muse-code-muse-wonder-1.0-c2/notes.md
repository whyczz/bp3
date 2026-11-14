# exp-6-hooks review — cycle 2

Verdict: ship

Claims (from EXPERIMENT.md Acceptance, all in test/hooks.sh unless noted):

- Garbage / foreign repo / unbound / reentrant / preset-with-no-run-folder:
  fail-open exit 0, no writes — fixtures pass.
- Bound Run: run_started (session_id on first) then run_settled;
  exactly one usage_recorded with summed PostLLMCall fields
  (150/15/4/3 in fixture) — pass.
- Killed session stale >900s swept run_unsettled; fresh parallel
  bindings swept nothing; ageing only one of two sweeps only it
  (test/hooks.sh:117-155, hooks.ml:173-180,281-299) — cycle-1
  blocker fixed.
- Refused bp3 q u -> refused {code, attempted}, state unchanged;
  lint exit -> lint_checked {check, pass|fail} — pass.
- Two parallel Runs: distinct bindings, no cross-talk — pass.
- Every event line: ts + run_id, no edge/from/to; fold skips it
  (state stays todo) — pass.
- Hook delivery: skills install writes .claude/hooks.json and
  merges same hooks into .claude/settings.json preserving other
  keys (test/skills.sh:66-73) — pass.

Gate: fresh `make check` exit 0 — shellcheck, check-skills (32),
skills (46 assertions), dune build, q, tape, hooks, induct all ok.
Code at HEAD identical to bound commit 31f362b for hooks.ml,
hooks.sh, skills.sh, bin/bp3 (empty diff).

Findings: no critical/major. Minor, already in EXPERIMENT.md
"Deliberately open": registry writes share one .tmp path with
no locking (hooks.ml:162-171); sequential hooks unaffected,
not an acceptance case. Comments in hooks.ml/bin/bp3 agree
with code (stale-gate and settings.json live-probe notes).

Live limit noted in exp: live usage_recorded carried zero
tokens on that host; fixture payloads with real usage sum
correctly, which is the acceptance case.

What would change my mind: a fixture or live run showing a
fresh binding swept, cross-talk, or a second usage_recorded.
