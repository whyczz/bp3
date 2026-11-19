#!/usr/bin/env bash
# fake-bp3 transcripts (test-pyramid js.1): the checked-in transcripts
# match a fresh recording from the real binary; a hand edit to one is
# caught, naming the argv that drifted; a second row for one call is
# refused by the check and by the fake (exit 96); a changed pid in
# bp3's own output drifts; and the fake refuses an argv it has no
# transcript for (exit 97) instead of guessing.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-transcripts.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { checks=$((checks + 1)); }
rec="$root/scripts/record-transcripts"

"$rec" --check > "$work/check.out" 2>&1 || fail "transcripts drifted from the real bp3: $(cat "$work/check.out")"; ok

# hand-edit one recorded call (init-check's stdout) in a copy
node -e '
const fs = require("fs");
const [src, dst] = process.argv.slice(1);
const rows = fs.readFileSync(src, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const row = rows.find((r) => r.argv.join(" ") === "harness init-check --engine pi");
if (!row) process.exit(3);
row.stdout = row.stdout.replace("\"ok\":true", "\"ok\":false");
fs.writeFileSync(dst, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
' "$root/test/fake-bp3/transcripts.jsonl" "$work/edited.jsonl" || fail "no init-check transcript to edit"
cmp -s "$root/test/fake-bp3/transcripts.jsonl" "$work/edited.jsonl" && fail "the hand edit changed nothing"
rc=0; RECORD_TRANSCRIPTS_FILE="$work/edited.jsonl" "$rec" --check > "$work/edited.out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a hand-edited transcript passed the check (exit $rc)"; ok
grep -q 'drift in stdout: harness init-check --engine pi' "$work/edited.out" || fail "the drift report does not name the argv: $(cat "$work/edited.out")"; ok

# a second row for one call, placed first (where the fake would find
# it): the check refuses the file, and so does the fake
node -e '
const fs = require("fs");
const [src, dst] = process.argv.slice(1);
const rows = fs.readFileSync(src, "utf8").split("\n").filter(Boolean);
const i = rows.findIndex((l) => JSON.parse(l).argv.join(" ") === "harness init-check --engine pi");
const dup = JSON.parse(rows[i]); dup.stdout = dup.stdout.replace("\"ok\":true", "\"ok\":false");
fs.writeFileSync(dst, [JSON.stringify(dup), ...rows].join("\n") + "\n");
' "$root/test/fake-bp3/transcripts.jsonl" "$work/dup.jsonl"
rc=0; RECORD_TRANSCRIPTS_FILE="$work/dup.jsonl" "$rec" --check > "$work/dup.out" 2>&1 || rc=$?
if [ "$rc" != 1 ] || ! grep -q 'duplicate transcript row.*harness init-check --engine pi' "$work/dup.out"; then
  fail "a duplicate transcript row passed the check (exit $rc): $(cat "$work/dup.out")"
fi; ok
git init -q "$work/dup-repo"
rc=0; (cd "$work/dup-repo" && FAKE_BP3_TRANSCRIPTS="$work/dup.jsonl" "$root/test/fake-bp3/bp3" harness init-check --engine pi > /dev/null 2> "$work/dup.err") || rc=$?
[ "$rc" = 96 ] || fail "the fake served a call with two rows (exit $rc): $(cat "$work/dup.err")"; ok

# the real binary, wrapped so every pid it prints reads 1: bp3's own
# pids are never normalized away, so the check reports drift
cat > "$work/pid-one-bp3" <<WRAP
#!/bin/sh
out=\$("$root/_build/default/src/quest/main.exe" "\$@"); rc=\$?
printf '%s\n' "\$out" | sed 's/"pid":[0-9][0-9]*/"pid":1/g'
exit \$rc
WRAP
chmod +x "$work/pid-one-bp3"
rc=0; RECORD_TRANSCRIPTS_REAL="$work/pid-one-bp3" "$rec" --check > "$work/pid.out" 2>&1 || rc=$?
if [ "$rc" != 1 ] || ! grep -q 'drift in stdout: harness watch --run-id R-live-1 --once' "$work/pid.out"; then
  fail "a changed pid in bp3's output did not drift (exit $rc): $(tail -5 "$work/pid.out")"
fi; ok

# an argv with no transcript: exit 97, named, nothing guessed
git init -q "$work/repo"
rc=0; (cd "$work/repo" && "$root/test/fake-bp3/bp3" q r no-such-quest > "$work/unknown.out" 2> "$work/unknown.err") || rc=$?
[ "$rc" = 97 ] || fail "unknown argv exit: $rc"; ok
grep -q 'no transcript for argv \["q","r","no-such-quest"\]' "$work/unknown.err" || fail "unknown argv not named: $(cat "$work/unknown.err")"; ok
[ ! -s "$work/unknown.out" ] || fail "the fake guessed an answer: $(cat "$work/unknown.out")"; ok
echo "transcripts tests: ok ($checks assertions)"
