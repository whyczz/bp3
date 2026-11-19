#!/bin/sh
# induct workflow contract tests (mock host, no agent calls).
set -eu
cd "$(dirname "$0")/.."
node test/node-loop.test.mjs
node test/induct-node.test.mjs
node test/induct-grade.test.mjs
node test/induct-land.test.mjs
node test/induct-conduct.test.mjs
