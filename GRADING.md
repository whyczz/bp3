# Grading bp3

Every grader brief that `bp3 q <quest> n <node> brief` renders carries
this file verbatim, read at the commit being graded, just before the
verdict shape. It holds the grade gate and the rules this repo adds to
the brief's own.

## Gate

Run `./scripts/receipt` from the desk (which runs `make check-full`,
`scripts/red-first`, and the `test/` line delta). Quote its exit code
and all 4 receipt lines. A grade that ran only `make check` has not run
the gate. Run `./scripts/receipt` alone in the grade desk; never run
`bp3 skills install` or `dune` concurrently with it.

## Depth and severity

- **Deterministic proofs first:** `scripts/red-first` proves changed
  tests fail on parent code (`BASE_FAIL_HEAD_PASS`). Do NOT hand-plant
  mutants per check in scratch copies; run **one** targeted adversarial
  probe on the single edge case the tests most likely miss.
- **Severity gate:** cast `needs_fix` ONLY for `[critical]` or `[major]`
  findings (broken gate, proven bug, unjustified deletion or weakening
  of existing tests, vacuous test that `red-first` missed, or a
  `CONSTRAINTS.md` violation). `[minor]` findings (wording, note counts,
  style) go under `FOLLOW-UPS` and the verdict is `ship`.
- **Docs/skill-only commits (`red-first: n/a`):** verify the gate
  (`make check-full`, `check-skills`, `check-retired-terms`) and the
  node's acceptance criteria directly; do not demand regex-pinning of
  every prose sentence.

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
