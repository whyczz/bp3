#!/usr/bin/env bash
# JS unit tier (test-pyramid js.1): the workflow tests (mock host) and
# the bp3-pi unit suite (fake bp3 replaying transcripts), all on
# node:test. Proves the tier launches no real bp3: every route to the
# real binary points at a counting shim, which must count 0. Reports
# the tier's time; slowness is read, never failed (red-ink R2').
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-js-unit.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
files=(test/node-loop.test.mjs test/induct-node.test.mjs test/induct-grade.test.mjs
  test/induct-land.test.mjs test/induct-conduct.test.mjs extensions/bp3-pi/test/bp3-pi.test.mjs)

for f in "${files[@]}"; do
  if grep -q 'main\.exe\|realBp3' "$root/$f"; then fail "$f names the real bp3 binary"; fi
done

shim="$work/counting-bp3"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 99\n' "$work/launches" > "$shim"
chmod +x "$shim"
"$shim" canary || true   # the shim must count, or a 0 below proves nothing
[ "$(wc -l < "$work/launches" | tr -d ' ')" = 1 ] || fail "the counting shim does not count"
: > "$work/launches"

rc=0
(cd "$root" && FAKE_BP3_MODE=replay FAKE_BP3_REAL="$shim" BP3_PI_REAL_BP3="$shim" \
  BP3_PI_TEST_BP3="$root/test/fake-bp3/bp3" node --test "${files[@]}") > "$work/out" 2>&1 || rc=$?
# launches first: a leak also fails tests (the shim exits 99), and the
# leak is the cause worth naming
n=$(wc -l < "$work/launches" | tr -d ' ')
[ "$n" = 0 ] || fail "the unit tier launched the real bp3 $n times: $(head -3 "$work/launches")"
[ "$rc" = 0 ] || { tail -40 "$work/out" >&2; fail "JS unit tier failed (exit $rc)"; }
tests=$(sed -n 's/^ℹ tests //p' "$work/out")
ms=$(sed -n 's/^ℹ duration_ms //p' "$work/out")
echo "js unit tier: ok ($tests tests, ${ms%.*}ms, 0 real bp3 launches)"
