# mig.1 handoff-verbs — run notes

## What changed
- FSM renamed in one sweep: `submit->handoff`, `review->grade`,
  `check->verify`, `submitted->handed_off` across OCaml core
  (`store/main/render/harness`), workflows (`induct-exp`,
  `induct-grade`), tests, completions, pi extension, plans, and
  skill sources; renders regenerated with
  `bp3 skills install --harness=all` (never hand-edited).
- The only compat mapping lives in `Store.fold_edge` /
  `fold_state_name` (fold-on-read). New ledger lines write new
  words only; old quest files and ledgers were not touched.
- Plan knobs renamed with the verbs (`grade_required`,
  `verify_required`; `grade:`/`verify:` keys in `plans/*.yaml`
  and the `init-repo` scaffold). Backtest `has_submit` became
  `has_handoff`.

## Decisions (naming discipline)
- Names reuse the settled QUEST.md table verbatim; internal
  identifiers (`grade_ok`, `gradePrompt`, run-id edge segments)
  follow the same words in the same change — no synonyms left.
- Not renamed, on purpose: harness `desk check` / `init-check`,
  hooks lint `check`, `make check`, pi roles `reviewer`/`checker`
  (worker roles, not FSM edges), and plain-English prose
  (design “review”, acceptance “check”). Those are different
  concepts sharing letters; renaming them would fork vocabulary.
- `test/q.sh` still contains old words only as frozen-ledger
  fixture data and the unknown-edge refusal loop — the compat
  proof itself, not live identifiers.

## Evidence
- Pre/post rollup over all 106 exps: identical except the two
  `submitted` exps now read `handed_off` (same cycle/commit).
- Fixture round-trip `handoff -> grade -> verify -> land`;
  old verbs refuse `E_USAGE unknown edge`.
- `make check` green (exit 0); new `test/q.sh` cases cover the
  frozen ledger, the mixed-vocab ledger, and old-edge refusal.
- This quest's own ledger stays mixed-vocab by design (minted
  `submit`, submitted `handoff`) and folds correctly throughout.
