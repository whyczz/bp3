# exp-followup-1-grade-evidence — handoff run notes

Run: 20261117T033939Z-handoff-muse-code-muse-wonder-1.0-c1 (handoff, cycle 1)

## What changed

- `skills/traverse/workflows/induct-grade.js` (+ synced
  `.agents/workflows/induct-grade.js` render):
  - Grade validations pipeline runs before the audit child
    spawns. Five deterministic plugs with owner-locked names
    (`validate_git_clean`, `validate_clean_commit`,
    `validate_run_folder_present`, `validate_handoff_by_child`,
    `validate_env_run_id_stamped`): ctx in, one typed evidence
    row out, expectation declared in the plug. A transport
    child only carries raw command output verbatim; plugs
    judge it. Empty stdout is quoted by code as
    `(empty stdout, exit 0)` — never hand-quoted by an LLM.
  - Audit brief now asks for acceptance rows only; adherence
    rows are never requested from the LLM again.
  - Untyped acceptance rows trigger one audit-internal
    re-collect naming the rows, inside the same audit Run (no
    new link mint, no FSM verdict, no cycle burn). Rows still
    untyped return outcome `audit_failure` naming the row and
    the collection error; grade/verify never spawn, so the
    ledger shows no author-facing verdict for paperwork.
  - Grade/verify parallel casts refused with
    `E_ILLEGAL_EDGE` after the sibling moved state are
    reported as an expected verdict race in `refusals`.
- `skills/traverse/SKILL.md` (+ installed renders): the grade
  evidence contract is named on the traverse surface —
  validations, audit-internal re-collect, `audit_failure`,
  expected verdict race.
- `test/induct-grade.test.mjs`: mock host gains a validations
  transport and per-call audit sequences; new fixtures cover
  re-collect approval (config.1 replay shape), audit_failure
  shape, a property sweep over untyped evidence shapes, the
  mvp.3 empty-stdout token, dirty-tree gating, and the named
  verdict race. `test/traverse-conduct.test.mjs` answers the
  validations transport in its fixture host.

## Lessons

- Missing evidence and real defects must take different
  roads all the way to the outcome word: `audit_failure`
  vs `needs_fix` is the distinction a conductor can act on
  without re-judging the matrix.
- Silence is evidence only when code mints the token; an
  LLM quoting `""` is indistinguishable from no evidence.
- A parallel-cast `E_ILLEGAL_EDGE` is information about
  ordering, not failure — name it where the outcome is read.

## Verification

- `node test/induct-grade.test.mjs`: ok
- `./test/traverse.sh`: ok (node-loop, induct-node,
  induct-grade, quest-land, traverse-conduct)
- `./test/skills.sh`: ok (123 assertions)
- `make check`: see tape.log for the full gate result.
