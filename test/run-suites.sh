#!/usr/bin/env bash
# run-suites fixtures (test-pyramid tier.1): HOME and env isolation,
# budget kills the whole process group, serial rows never overlap,
# table validation, --list and --report. Planted suites live in
# test/run-suites/.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
rs="$root/scripts/run-suites"
p="$root/test/run-suites"
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-run-suites.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { checks=$((checks + 1)); }
T=$(printf '\t')
row() { # name tier cmd budget serial why
  printf '%s\n' "$1$T$2$T$3$T$4$T$5$T$6${T}test/run-suites/*"
}
{
  row leak fixture "bash $p/leak.sh" 5 0 -
  row envprobe fixture "bash $p/envprobe.sh $work/env.out" 5 0 -
  row sleeper fixture "bash $p/sleeper.sh $work/sleeper.pid" 2 0 -
  row serial-a fixture "bash $p/lock.sh $work/lock-s" 5 1 -
  row serial-b fixture "bash $p/lock.sh $work/lock-s" 5 1 -
  row free-a fixture "bash $p/lock.sh $work/lock-f" 5 0 -
  row free-b fixture "bash $p/lock.sh $work/lock-f" 5 0 -
} > "$work/t.tsv"
mkdir -p "$work/realhome"

# 1. HOME and env: the caller's HOME and leaking vars never reach a suite
HOME="$work/realhome" GIT_DIR=/nonexistent BP3_DECIDER=x \
  "$rs" --table "$work/t.tsv" --only leak,envprobe > "$work/iso.out" 2>&1 || fail "isolation run: $(cat "$work/iso.out")"
[ ! -e "$work/realhome/.bp3-leak" ] || fail "suite wrote the caller's HOME"; ok
! grep -q '^GIT_DIR=' "$work/env.out" || fail "GIT_DIR leaked into a suite"; ok
! grep -q '^BP3_DECIDER=' "$work/env.out" || fail "BP3_DECIDER leaked into a suite"; ok
grep -q '^BP3_SUITE=envprobe$' "$work/env.out" || fail "BP3_SUITE missing"; ok
grep -q '^GIT_CONFIG_NOSYSTEM=1$' "$work/env.out" || fail "GIT_CONFIG_NOSYSTEM missing"; ok
home=$(sed -n 's/^HOME=//p' "$work/env.out")
[ -n "$home" ] && [ "$home" != "$work/realhome" ] || fail "suite HOME not isolated: $home"; ok
grep -q "^TMPDIR=$home/t$" "$work/env.out" || fail "suite TMPDIR not under its HOME"; ok

# 2. budget: an overrun fails by name, fast, and the whole group dies
start=$(date +%s)
if "$rs" --table "$work/t.tsv" --only sleeper > "$work/budget.out" 2>&1; then fail "budget overrun passed"; fi
[ $(( $(date +%s) - start )) -le 4 ] || fail "budget kill took over 4s"; ok
grep -q 'FAIL.*sleeper.*budget exceeded' "$work/budget.out" || fail "overrun not named: $(cat "$work/budget.out")"; ok
child=$(cat "$work/sleeper.pid")
if kill -0 "$child" 2>/dev/null; then fail "sleeper's child survived the group kill"; fi; ok

# 3. serial rows never overlap; the same rows without the flag do
"$rs" --table "$work/t.tsv" --only serial-a,serial-b --jobs 4 > "$work/serial.out" 2>&1 || fail "serial rows overlapped: $(cat "$work/serial.out")"; ok
if "$rs" --table "$work/t.tsv" --only free-a,free-b --jobs 4 > "$work/free.out" 2>&1; then fail "control: non-serial rows did not overlap, so the serial check proves nothing"; fi; ok

# 4. table validation and selection
printf '%s\n' "slowpoke${T}slow${T}true${T}5${T}0${T}-${T}-" > "$work/bad.tsv"
set +e; "$rs" --table "$work/bad.tsv" > "$work/bad.out" 2>&1; rc=$?; set -e
if [ "$rc" != 2 ] || ! grep -q 'needs a why' "$work/bad.out"; then fail "slow row without why accepted (rc=$rc)"; fi; ok
set +e; "$rs" --table "$work/t.tsv" --only nope > /dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "unknown suite rc=$rc"; ok
[ "$("$rs" --table "$work/t.tsv" --only leak,envprobe --list | tr '\n' ' ')" = "leak envprobe " ] || fail "--list"; ok

# 5. --report prints actual vs budget for every selected row
"$rs" --table "$work/t.tsv" --only leak,envprobe --report > "$work/report.out" 2>&1 || fail "report run"
if ! grep -E -q '%  leak +[0-9.]+/5s' "$work/report.out" || ! grep -E -q '%  envprobe +[0-9.]+/5s' "$work/report.out"; then fail "report rows: $(cat "$work/report.out")"; fi; ok

# 6. the real table parses and every slow row carries a why
"$rs" --list > /dev/null || fail "test/suites.tsv does not parse"; ok
echo "run-suites tests: ok ($checks assertions)"
