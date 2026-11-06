# bp3 toy

A deliberately red OCaml project for the permanent coordination drills.

- `dune exec ./hello.exe` initially prints `not implemented`.
- `dune runtest` expects exactly `hello` plus newline and initially fails.
- The Worker must implement `hello.ml`, not weaken `expected.txt`.
- A blocker drill instead names `./missing-check`; the Worker must ask through
  the Board and wait for the human's check decision, not invent that script.

Materialize with `tests/materialize-toy /absolute/new/path` from bp3. This
creates a fresh Git repository and `quest/toy` integration branch. It never
writes over an existing directory. The bp3 root test suite does not execute
this intentionally failing nested project's checks.
