#!/bin/sh
# traverse workflow contract tests (mock host, no agent calls).
set -eu
cd "$(dirname "$0")/.."
node test/node-loop.test.mjs
node test/induct-grade.test.mjs
node test/quest-land.test.mjs
