# followup.4 bind-resolution — run notes

- Scan resolution now narrows by the Run's own edge: when several tapes
  reference a Run, only the tape whose entry binds `BP3_RUN_ID=<run>` to
  `bp3 q ... u <exp> <edge>` (edge = run-id's second segment, exp from
  the InitRecord) resolves; zero or several such tapes refuse
  `E_AMBIGUOUS` naming every candidate. One candidate passes through as
  before, and an InitRecord/binding-named tape still wins over any scan.
- The rule is shared: `narrow_candidates` in `src/quest/harness.ml` is
  used by both `find-tape` and `watch`; help text for both verbs states
  the rule.
- Fixtures in `test/harness.sh` (followup.4 section) shape the real
  sibling set: init (`record-init`), resolve (`find-tape`), quoting
  conductor, and author (`submit`) tapes for one Run, plus no-own-edge
  and two-own-edge refusals. `make check` green.
- Lesson: co-occurrence must be per tape entry, not per file — sibling
  sessions all mention the run-id, but only the author's entry binds
  the id to its own edge call.
