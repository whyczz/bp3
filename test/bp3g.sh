#!/bin/sh
# bp3g workflow contract tests (mock host, no agent calls).
set -eu
cd "$(dirname "$0")/.."
node test/node-loop.test.mjs
node test/bp3g-node.test.mjs
node test/bp3g-grade.test.mjs
node test/bp3g-land.test.mjs
node test/bp3g-conduct.test.mjs
