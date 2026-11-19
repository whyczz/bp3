#!/usr/bin/env bash
# harness suite, all pieces in order (test-pyramid tier.1 split).
# run-suites runs each piece as its own suite, in parallel;
# this file keeps the single-command run for make check.
set -euo pipefail
dir=$(cd "$(dirname "$0")/harness" && pwd)
for piece in cli fold watch supervisor race evidence backtest; do
  bash "$dir/$piece.sh"
done
echo "harness.sh: all checks passed"
