#!/bin/sh
# induct-exp workflow contract test (mock host, no agent calls).
set -eu
cd "$(dirname "$0")/.."
node test/induct-exp.test.mjs
