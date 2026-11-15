#!/bin/sh
# induct workflow contract tests (mock host, no agent calls).
set -eu
cd "$(dirname "$0")/.."
node test/induct-exp.test.mjs
node test/induct-grade.test.mjs
