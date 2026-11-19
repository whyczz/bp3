#!/usr/bin/env bash
# run-suites fixtures (test-pyramid tier.1): HOME and env isolation,
# budget kills the whole process group and never fires early, a
# terminal Ctrl-C reaps every suite, serial rows never overlap,
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
  row near fixture "sleep 1.5" 2 0 -
  row hold fixture "bash $p/sleeper.sh $work/hold.pid" 30 0 -
} > "$work/t.tsv"
mkdir -p "$work/realhome"

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
if "$rs" --table "$work/t.tsv" --only sleeper > "$work/budget.out" 2>&1; then fail "budget overrun passed"; fi
[ $(( $(date +%s) - start )) -le 4 ] || fail "budget kill took over 4s"; ok
grep -q 'FAIL.*sleeper.*budget exceeded' "$work/budget.out" || fail "overrun not named: $(cat "$work/budget.out")"; ok
child=$(cat "$work/sleeper.pid")
if kill -0 "$child" 2>/dev/null; then fail "sleeper's child survived the group kill"; fi; ok
if grep -E -q 'Terminated|Killed|setpgid' "$work/budget.out"; then fail "job-control noise in runner output: $(cat "$work/budget.out")"; fi; ok

# 2b. a budget fires only on a real overrun: 1.5s inside 2s passes, every time
for n in 1 2 3; do
  "$rs" --table "$work/t.tsv" --only near > "$work/near.out" 2>&1 || fail "1.5s suite killed under a 2s budget (run $n): $(cat "$work/near.out")"
done; ok

# 2b'. suites start with default INT/QUIT (bash ignores them for `&`
# commands when job control is off; the runner must undo that)
printf '%s\n' "sigs${T}fixture${T}perl -e 'print \"INT=\", (\$SIG{INT} // \"DEFAULT\"), \"\\n\"' > $work/sigs.out${T}5${T}0${T}-${T}-" > "$work/sigs.tsv"
"$rs" --table "$work/sigs.tsv" > /dev/null 2>&1 || fail "signal probe run"
grep -q '^INT=DEFAULT$' "$work/sigs.out" || fail "suite started with INT not default: $(cat "$work/sigs.out")"; ok

# 2c. a terminal Ctrl-C reaps every running suite and the runner's temp dir
mkdir -p "$work/rt"
cat > "$work/ctrlc.py" <<'PY'
# usage: ctrlc.py <ready-file> <cmd...>: run cmd on a pty, wait for
# ready-file (it holds a suite's child pid), type Ctrl-C, then report
# cmd's exit code and whether that pid survived -- checked while the
# pty is still open, since closing it would SIGHUP orphans for us
import os, pty, select, sys, time
ready, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
def drain():  # never block: a blocking read would delay the Ctrl-C
    while select.select([fd], [], [], 0)[0]:
        try:
            if not os.read(fd, 4096): return
        except OSError: return
end = time.time() + 15
while time.time() < end and not os.path.exists(ready):
    drain(); time.sleep(0.05)
time.sleep(0.5)
os.write(fd, b"\x03")
end = time.time() + 10
while time.time() < end:
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        print(os.waitstatus_to_exitcode(status))
        time.sleep(0.5)
        held = int(open(ready).read().strip())
        try:
            os.kill(held, 0); print("suite alive")
        except ProcessLookupError:
            print("suite dead")
        sys.exit(0)
    drain(); time.sleep(0.05)
print("hung"); sys.exit(1)
PY
TMPDIR="$work/rt" python3 "$work/ctrlc.py" "$work/hold.pid" "$rs" --table "$work/t.tsv" --only hold > "$work/ctrlc.out" 2>&1 || true
grep -q '^130$' "$work/ctrlc.out" || fail "Ctrl-C exit code: $(cat "$work/ctrlc.out")"; ok
[ -s "$work/hold.pid" ] || fail "Ctrl-C probe: the held suite never started"
grep -q '^suite dead$' "$work/ctrlc.out" || { kill "$(cat "$work/hold.pid")" 2>/dev/null; fail "Ctrl-C left a suite running: $(cat "$work/ctrlc.out")"; }; ok
[ -z "$(ls "$work/rt")" ] || fail "Ctrl-C left the runner temp dir: $(ls "$work/rt")"; ok

# 3. serial rows never overlap; the same rows without the flag do
"$rs" --table "$work/t.tsv" --only serial-a,serial-b --jobs 4 > "$work/serial.out" 2>&1 || fail "serial rows overlapped: $(cat "$work/serial.out")"; ok
if "$rs" --table "$work/t.tsv" --only free-a,free-b --jobs 4 > "$work/free.out" 2>&1; then fail "control: non-serial rows did not overlap, so the serial check proves nothing"; fi; ok

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

# 5. --report prints actual vs budget for every selected row
"$rs" --table "$work/t.tsv" --only leak,envprobe --report > "$work/report.out" 2>&1 || fail "report run"
if ! grep -E -q '%  leak +[0-9.]+/5s' "$work/report.out" || ! grep -E -q '%  envprobe +[0-9.]+/5s' "$work/report.out"; then fail "report rows: $(cat "$work/report.out")"; fi; ok

# 6. the real table parses and every slow row carries a why
"$rs" --list > /dev/null || fail "test/suites.tsv does not parse"; ok
echo "run-suites tests: ok ($checks assertions)"
