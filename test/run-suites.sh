#!/usr/bin/env bash
# run-suites fixtures (test-pyramid tier.1), black-box against
# scripts/run-suites (the OCaml runner): HOME and env isolation,
# budget kills the whole process group and never fires early, Ctrl-C
# (once or mashed), Ctrl-\ and SIGHUP reap every suite and the temp
# dir, serial rows never overlap, table validation, --list and
# --report. Planted suites live in test/run-suites/. TMPDIR points
# inside $work for the whole test, so nothing leaks.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
rs="$root/scripts/run-suites"
p="$root/test/run-suites"
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-run-suites.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# every runner call below makes its temp dir inside $work, so a run that
# fails on purpose (and keeps its logs) never leaks into the caller's TMPDIR
mkdir "$work/tmp"; export TMPDIR="$work/tmp"
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
  row near fixture "sleep 1.5" 2 0 -
  row hold fixture "bash $p/sleeper.sh $work/hold.pid" 30 0 -
} > "$work/t.tsv"
mkdir -p "$work/realhome" "$work/kept"

# 1. HOME and env: the caller's HOME and leaking vars never reach a suite
HOME="$work/realhome" GIT_DIR=/nonexistent BP3_DECIDER=x LC_MESSAGES=C \
  "$rs" --table "$work/t.tsv" --only leak,envprobe > "$work/iso.out" 2>&1 || fail "isolation run: $(cat "$work/iso.out")"
[ ! -e "$work/realhome/.bp3-leak" ] || fail "suite wrote the caller's HOME"; ok
! grep -q '^GIT_DIR=' "$work/env.out" || fail "GIT_DIR leaked into a suite"; ok
! grep -q '^BP3_DECIDER=' "$work/env.out" || fail "BP3_DECIDER leaked into a suite"; ok
grep -q '^BP3_SUITE=envprobe$' "$work/env.out" || fail "BP3_SUITE missing"; ok
grep -q '^GIT_CONFIG_NOSYSTEM=1$' "$work/env.out" || fail "GIT_CONFIG_NOSYSTEM missing"; ok
grep -q '^LC_MESSAGES=C$' "$work/env.out" || fail "LC_* not passed through"; ok
home=$(sed -n 's/^HOME=//p' "$work/env.out")
[ -n "$home" ] && [ "$home" != "$work/realhome" ] || fail "suite HOME not isolated: $home"; ok
grep -q "^TMPDIR=$home/t$" "$work/env.out" || fail "suite TMPDIR not under its HOME"; ok

# 2. budget: an overrun fails by name, fast, and the whole group dies
start=$(date +%s)
if TMPDIR="$work/kept" "$rs" --table "$work/t.tsv" --only sleeper > "$work/budget.out" 2>&1; then fail "budget overrun passed"; fi
[ $(( $(date +%s) - start )) -le 4 ] || fail "budget kill took over 4s"; ok
grep -q 'FAIL.*sleeper.*budget exceeded' "$work/budget.out" || fail "overrun not named: $(cat "$work/budget.out")"; ok
child=$(cat "$work/sleeper.pid")
if kill -0 "$child" 2>/dev/null; then fail "sleeper's child survived the group kill"; fi; ok
if grep -E -q 'Terminated|Killed|setpgid' "$work/budget.out"; then fail "job-control noise in runner output: $(cat "$work/budget.out")"; fi; ok
if find "$work/kept" -path '*/sleeper/home' | grep -q .; then fail "a failed suite kept its HOME, not just its log"; fi; ok
find "$work/kept" -path '*/sleeper/log' | grep -q . || fail "a failed suite lost its log"; ok

# 2a'. a suite launched after kills in the same tick is not charged for
# them. The hangs carry the larger budget so they launch first (largest
# budget first) and fill both jobs; honest starts only after both are
# killed, 0.6s of kill pauses into that tick
printf '%s\n' "hang1${T}fixture${T}sleep 999${T}3${T}0${T}-${T}-" "hang2${T}fixture${T}sleep 999${T}3${T}0${T}-${T}-" \
  "honest${T}fixture${T}sleep 1.6${T}2${T}0${T}-${T}-" > "$work/honest.tsv"
for n in 1 2; do
  TMPDIR="$work/kept" "$rs" --table "$work/honest.tsv" --jobs 2 > "$work/honest.out" 2>&1 || true
  grep -q '^  ok   honest' "$work/honest.out" || fail "a 1.6s suite failed its 2s budget after same-tick kills (run $n): $(cat "$work/honest.out")"
done; ok

# 2b. a budget fires only on a real overrun: 1.5s inside 2s passes, every time
for n in 1 2 3; do
  "$rs" --table "$work/t.tsv" --only near > "$work/near.out" 2>&1 || fail "1.5s suite killed under a 2s budget (run $n): $(cat "$work/near.out")"
done; ok

# 2b'. suites start with default INT and QUIT, even when the runner
# inherited them ignored (bash ignores both for `&` commands when job
# control is off, as here): a suite signalled directly dies of it
# (128 + N) instead of riding out its budget. SIGPIPE too: the runner
# ignores it for itself, and a suite must not inherit that
{
  for sig in INT QUIT; do
    printf '%s\n' "sig-$sig${T}fixture${T}echo \$\$ > $work/sig-$sig.pid; exec sleep 30${T}5${T}0${T}-${T}-"
  done
  printf '%s\n' "sig-PIPE${T}fixture${T}kill -PIPE \$\$; exit 0${T}5${T}0${T}-${T}-"
} > "$work/sigs.tsv"
"$rs" --table "$work/sigs.tsv" > "$work/sigs.out" 2>&1 &
rsp=$!
for sig in INT QUIT; do
  for _ in $(seq 50); do [ -s "$work/sig-$sig.pid" ] && break; sleep 0.1; done
  kill -"$sig" "$(cat "$work/sig-$sig.pid")" || fail "signal probe: no sig-$sig suite to signal"
done
rc=0; wait "$rsp" || rc=$?
[ "$rc" = 1 ] || fail "signal probe exit: $rc ($(cat "$work/sigs.out"))"
grep -Eq 'FAIL sig-INT .*rc=130$' "$work/sigs.out" || fail "suite did not die of INT: $(cat "$work/sigs.out")"; ok
grep -Eq 'FAIL sig-QUIT .*rc=131$' "$work/sigs.out" || fail "suite did not die of QUIT: $(cat "$work/sigs.out")"; ok
grep -Eq 'FAIL sig-PIPE .*rc=141$' "$work/sigs.out" || fail "suite started with SIGPIPE ignored: $(cat "$work/sigs.out")"; ok

# 2c. a terminal Ctrl-C reaps every running suite and the runner's temp
# dir. A terminal sends ^C (INT) and ^\ (QUIT) to its foreground process
# group; here the runner gets its own group (set -m for the launch, which
# also starts it with INT and QUIT at their defaults) and the probe
# signals that group. Suites run in their own sessions, so only the
# runner hears it and must reap them. No pty (owner, 2026-11-20).
mkdir -p "$work/rt"
for probe in INT:1:130 INT:3:130 QUIT:1:131; do
  sig=${probe%%:*} rest=${probe#*:}
  times=${rest%%:*} code=${rest##*:}
  rm -f "$work/hold.pid"
  set -m
  TMPDIR="$work/rt" "$rs" --table "$work/t.tsv" --only hold > "$work/ctrlc.out" 2>&1 &
  rpid=$!
  set +m
  n=0; while [ ! -s "$work/hold.pid" ] && [ $n -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
  [ -s "$work/hold.pid" ] || fail "$sig x$times probe: the held suite never started"
  sleep 0.5
  kill -"$sig" -- -"$rpid" || fail "$sig x$times probe: no runner group to signal"
  # mashed: later presses may find the group already gone
  i=1; while [ $i -lt "$times" ]; do sleep 0.3; kill -"$sig" -- -"$rpid" 2>/dev/null || break; i=$((i + 1)); done
  rc=0; wait "$rpid" || rc=$?
  [ "$rc" = "$code" ] || fail "$sig x$times exit code (want $code): $rc ($(cat "$work/ctrlc.out"))"; ok
  sleep 0.5
  if kill -0 "$(cat "$work/hold.pid")" 2>/dev/null; then kill "$(cat "$work/hold.pid")"; fail "$sig x$times left a suite running: $(cat "$work/ctrlc.out")"; fi; ok
  [ -z "$(ls "$work/rt")" ] || fail "$sig x$times left the runner temp dir: $(ls "$work/rt")"; ok
  if grep -E -q 'Quit:|Terminated|Killed' "$work/ctrlc.out"; then fail "$sig x$times printed shell notices: $(cat "$work/ctrlc.out")"; fi; ok
done

# 2c'. a signal that lands between a suite's fork and its bookkeeping
# still reaps it: the runner's test hook signals itself inside that
# window (where INT/TERM/HUP/QUIT are blocked), then nothing may survive
# a name unique to this run, so parallel self-tests never collide. A
# symlink, not a copy: macOS kills a copied system binary at exec
# (code-signing launch constraint), which would make this probe vacuous.
ln -s "$(command -v sleep)" "$work/forkwin-sleep"
"$work/forkwin-sleep" 0 || fail "fork-window probe: the marker binary does not run"
printf '%s\n' "forkwin${T}fixture${T}$work/forkwin-sleep 997${T}60${T}0${T}-${T}-" > "$work/forkwin.tsv"
rc=0; TMPDIR="$work/rt" RUN_SUITES_SIGNAL_AFTER_FORK=INT "$rs" --table "$work/forkwin.tsv" > "$work/forkwin.out" 2>&1 || rc=$?
[ "$rc" = 130 ] || fail "fork-window probe exit: $rc ($(cat "$work/forkwin.out"))"
sleep 1.5
if pgrep -f "$work/forkwin-sleep" > /dev/null; then pkill -f "$work/forkwin-sleep"; fail "a suite forked just before the signal survived"; fi; ok
[ -z "$(ls "$work/rt")" ] || fail "fork-window probe left the runner temp dir"; ok

# 2d. SIGHUP (terminal closed) and SIGTERM reap, clean up, and print no
# job notices. Suites run in their own sessions, so a signal the runner
# misses would orphan every one of them
for sig in HUP:129 TERM:143; do
  name=${sig%%:*} want=${sig##*:}
  rm -f "$work/hold.pid"
  TMPDIR="$work/rt" "$rs" --table "$work/t.tsv" --only hold > "$work/hup.out" 2>&1 &
  rpid=$!
  n=0; while [ ! -s "$work/hold.pid" ] && [ $n -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
  [ -s "$work/hold.pid" ] || fail "$name probe: the held suite never started"
  kill -"$name" "$rpid"
  rc=0; wait "$rpid" || rc=$?
  [ "$rc" = "$want" ] || fail "$name exit code: $rc"; ok
  if kill -0 "$(cat "$work/hold.pid")" 2>/dev/null; then kill "$(cat "$work/hold.pid")"; fail "$name left a suite running"; fi; ok
  [ -z "$(ls "$work/rt")" ] || fail "$name left the runner temp dir: $(ls "$work/rt")"; ok
  if grep -E -q 'Terminated|Killed' "$work/hup.out"; then fail "job notices on the $name path: $(cat "$work/hup.out")"; fi; ok
done

# 2d'. a closed reader (`run-suites | head -1`) reaps the running suites,
# removes the temp dir and exits 2 with one line, no crash report
ln -s "$(command -v sleep)" "$work/pipe-sleep"
printf '%s\n' "quick${T}fixture${T}sleep 0.5${T}5${T}0${T}-${T}-" \
  "held${T}fixture${T}echo \$\$ > $work/pipe.pid; exec $work/pipe-sleep 30${T}60${T}0${T}-${T}-" > "$work/pipe.tsv"
mkdir -p "$work/rp"
{ rc=0; TMPDIR="$work/rp" "$rs" --table "$work/pipe.tsv" 2> "$work/pipe.err" || rc=$?; echo "$rc" > "$work/pipe.rc"; } | head -1 > /dev/null
[ "$(cat "$work/pipe.rc")" = 2 ] || fail "closed reader exit: $(cat "$work/pipe.rc") ($(cat "$work/pipe.err"))"; ok
if pgrep -f "$work/pipe-sleep" > /dev/null; then pkill -f "$work/pipe-sleep"; fail "a closed reader left a suite running"; fi; ok
[ -z "$(ls "$work/rp")" ] || fail "a closed reader left the runner temp dir"; ok
if ! grep -q 'Broken pipe' "$work/pipe.err" || grep -q 'Fatal error' "$work/pipe.err"; then fail "closed reader stderr: $(cat "$work/pipe.err")"; fi; ok

# 2e. launch order: the largest budget starts first, whatever its row
printf '%s\n' "short1${T}fixture${T}true${T}5${T}0${T}-${T}-" "short2${T}fixture${T}true${T}5${T}0${T}-${T}-" \
  "long${T}fixture${T}true${T}90${T}0${T}-${T}-" > "$work/order.tsv"
"$rs" --table "$work/order.tsv" --jobs 1 > "$work/order.out" 2>&1 || fail "order run: $(cat "$work/order.out")"
[ "$(grep -E '^  ok ' "$work/order.out" | awk '{print $2}' | tr '\n' ' ')" = "long short1 short2 " ] || fail "launch order not largest budget first: $(cat "$work/order.out")"; ok
[ "$("$rs" --table "$work/order.tsv" --list | tr '\n' ' ')" = "short1 short2 long " ] || fail "--list must keep table order"; ok

# 2f. a passing suite's background children die with it
ln -s "$(command -v sleep)" "$work/strag-sleep"
printf '%s\n' "strag${T}fixture${T}$work/strag-sleep 30 & echo \$! > $work/strag.pid; exit 0${T}5${T}0${T}-${T}-" > "$work/strag.tsv"
"$rs" --table "$work/strag.tsv" > "$work/strag.out" 2>&1 || fail "straggler probe run: $(cat "$work/strag.out")"
[ -s "$work/strag.pid" ] || fail "straggler probe: no child pid recorded"
n=0; while pgrep -f "$work/strag-sleep" > /dev/null && [ $n -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
if pgrep -f "$work/strag-sleep" > /dev/null; then pkill -f "$work/strag-sleep"; fail "a passing suite's background child survived it"; fi; ok

# 3. serial rows never overlap; the same rows without the flag do
"$rs" --table "$work/t.tsv" --only serial-a,serial-b --jobs 4 > "$work/serial.out" 2>&1 || fail "serial rows overlapped: $(cat "$work/serial.out")"; ok
if TMPDIR="$work/kept" "$rs" --table "$work/t.tsv" --only free-a,free-b --jobs 4 > "$work/free.out" 2>&1; then fail "control: non-serial rows did not overlap, so the serial check proves nothing"; fi; ok

# 4. table validation and selection
printf '%s\n' "slowpoke${T}slow${T}true${T}5${T}0${T}-${T}-" > "$work/bad.tsv"
printf '%s\n' "wide${T}fixture${T}true${T}5${T}0${T}-${T}-${T}extra" > "$work/wide.tsv"
set +e; "$rs" --table "$work/wide.tsv" > "$work/wide.out" 2>&1; rc=$?; set -e
if [ "$rc" != 2 ] || ! grep -q 'expected 7 tab-separated fields, got 8' "$work/wide.out"; then fail "8-field row accepted (rc=$rc)"; fi; ok
set +e; "$rs" --table "$work/t.tsv" --only '' > /dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "empty --only rc=$rc"; ok
set +e; "$rs" --table "$work/t.tsv" --tier fixture,bogus > /dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "unknown tier rc=$rc"; ok
set +e; "$rs" --table "$work/bad.tsv" > "$work/bad.out" 2>&1; rc=$?; set -e
if [ "$rc" != 2 ] || ! grep -q 'needs a why' "$work/bad.out"; then fail "slow row without why accepted (rc=$rc)"; fi; ok
set +e; "$rs" --table "$work/t.tsv" --only nope > /dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "unknown suite rc=$rc"; ok
[ "$("$rs" --table "$work/t.tsv" --only leak,envprobe --list | tr '\n' ' ')" = "leak envprobe " ] || fail "--list"; ok
[ "$(cd "$work" && "$rs" --table t.tsv --only leak --list)" = "leak" ] || fail "relative --table not read from the caller's directory"; ok

# 5. --report prints actual vs budget for every selected row
"$rs" --table "$work/t.tsv" --only leak,envprobe --report > "$work/report.out" 2>&1 || fail "report run"
if ! grep -E -q '%  leak +[0-9.]+/5s' "$work/report.out" || ! grep -E -q '%  envprobe +[0-9.]+/5s' "$work/report.out"; then fail "report rows: $(cat "$work/report.out")"; fi; ok

# 6. the real table parses and every slow row carries a why
"$rs" --list > /dev/null || fail "test/suites.tsv does not parse"; ok
echo "run-suites tests: ok ($checks assertions)"
