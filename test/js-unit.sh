#!/usr/bin/env bash
# JS unit tier (test-pyramid js.1): the workflow tests (mock host) and
# the bp3-pi unit suite (fake bp3 replaying transcripts), all on
# node:test. Proves the tier launches no real bp3: it runs in a scratch
# copy of the repo whose real entry points (_build/.../main.exe and
# bin/bp3) are counting shims, with every env route aimed at the same
# shim, so any launch is counted whatever path a test builds. Reports
# the tier's time; slowness is read, never failed (red-ink R2').
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-js-unit.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
files=(test/node-loop.test.mjs test/induct-node.test.mjs test/induct-grade.test.mjs
  test/induct-land.test.mjs test/induct-conduct.test.mjs extensions/bp3-pi/test/bp3-pi.test.mjs)

copy="$work/repo"
mkdir "$copy"
(cd "$root" && tar --exclude ./_build --exclude ./.git --exclude ./.bp3 --exclude ./docs -cf - .) | (cd "$copy" && tar -xf -)
shim="$work/counting-bp3"
# shellcheck disable=SC2016  # $0 and $* belong to the shim, not this script
printf '#!/bin/sh\necho "$0 $*" >> "%s"\nexit 99\n' "$work/launches" > "$shim"
chmod +x "$shim"
mkdir -p "$copy/_build/default/src/quest" "$work/path"
cp "$shim" "$copy/_build/default/src/quest/main.exe"
cp "$shim" "$copy/bin/bp3"
cp "$shim" "$work/path/bp3"      # the installed names, first on PATH
cp "$shim" "$work/path/bp3-q"
# every shim must count, or a 0 below proves nothing
for s in "$shim" "$copy/_build/default/src/quest/main.exe" "$copy/bin/bp3" "$work/path/bp3" "$work/path/bp3-q"; do "$s" canary || true; done
[ "$(wc -l < "$work/launches" | tr -d ' ')" = 5 ] || fail "the counting shims do not count"
: > "$work/launches"
# an absolute path back into the real repo would escape the copy's shims
if grep -rlF "$root" "$copy/test" "$copy/extensions" > "$work/abs" 2>/dev/null; then
  fail "the unit tier names the real repo by absolute path: $(cat "$work/abs")"
fi

rc=0
(cd "$copy" && PATH="$work/path:$PATH" FAKE_BP3_MODE=replay FAKE_BP3_REAL="$shim" BP3_PI_REAL_BP3="$shim" BP3_Q_BIN="$shim" \
  BP3_PI_TEST_BP3="$copy/test/fake-bp3/bp3" node --test "${files[@]}") > "$work/out" 2>&1 || rc=$?
# launches first: a leak also fails tests (the shims exit 99), and the
# leak is the cause worth naming
n=$(wc -l < "$work/launches" | tr -d ' ')
[ "$n" = 0 ] || fail "the unit tier launched the real bp3 $n times: $(head -3 "$work/launches")"
[ "$rc" = 0 ] || { tail -40 "$work/out" >&2; fail "JS unit tier failed (exit $rc)"; }
tests=$(sed -n 's/^ℹ tests //p' "$work/out")
ms=$(sed -n 's/^ℹ duration_ms //p' "$work/out")
echo "js unit tier: ok ($tests tests, ${ms%.*}ms, 0 real bp3 launches)"
