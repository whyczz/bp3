# Grading bp3

Every grader brief that `bp3 q <quest> n <node> brief` renders ends
with this file, verbatim, read at the commit being graded. It holds the
grade gate and the rules this repo adds to the brief's own.

## Gate

Run `make check-full` from the desk, the grade gate. Quote its exit code
and its last lines. A grade that ran only `make check` has not run the
gate.

## Rules

- Build with `dune build --root .` when you need the binary.
- Never `rm -rf` a path held in a variable.
- Never run `bp3 init` or `bp3 skills install` unless
  `BP3_COMPLETIONS_DIR` points at a fresh scratch directory. Without it,
  they write the owner's global zsh completion.
- Never run `bp3 q <quest> metrics scrape` against a real quest. Use a
  scratch clone.
- `CONSTRAINTS.md` is the owner-signed stack. A commit that adds a
  language, library or surface outside it is `needs_fix`, owner class.
  So is a diff to `CONSTRAINTS.md` without a new dated owner-words row
  in its Sign-off log.
- A check you mean to claim must be seen to fail on the bug it guards:
  plant the bug in a scratch copy and watch the check go red. A claim
  you didn't see fail is reported as unverified, not as a finding.
