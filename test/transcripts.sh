#!/usr/bin/env bash
# fake-bp3 transcripts (test-pyramid js.1): the checked-in transcripts
# match a fresh recording from the real binary; a hand edit to one is
# caught, naming the argv that drifted; and the fake refuses an argv it
# has no transcript for (exit 97) instead of guessing.
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

# an argv with no transcript: exit 97, named, nothing guessed
git init -q "$work/repo"
rc=0; (cd "$work/repo" && "$root/test/fake-bp3/bp3" q r no-such-quest > "$work/unknown.out" 2> "$work/unknown.err") || rc=$?
[ "$rc" = 97 ] || fail "unknown argv exit: $rc"; ok
grep -q 'no transcript for argv \["q","r","no-such-quest"\]' "$work/unknown.err" || fail "unknown argv not named: $(cat "$work/unknown.err")"; ok
[ ! -s "$work/unknown.out" ] || fail "the fake guessed an answer: $(cat "$work/unknown.out")"; ok
echo "transcripts tests: ok ($checks assertions)"
