#!/usr/bin/env bash
# harness suite, every piece (test-pyramid tier.1 split): the rows of
# test/suites.tsv named harness-*, run in parallel through run-suites.
# A convenience entry point only; the table is the one list of pieces.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
only=$("$root/scripts/run-suites" --list | grep '^harness-' | paste -sd, -)
[ -n "$only" ] || { echo "harness.sh: no harness-* rows in test/suites.tsv" >&2; exit 1; }
exec "$root/scripts/run-suites" --only "$only"
