#!/usr/bin/env bash
# Fixture tests for scripts/receipt (fast-agy-induct verify.2).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-receipt-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

n=0
expect() {
  local label="$1" want="$2" got="$3"
  n=$((n + 1))
  if [ "$want" != "$got" ]; then
    echo "FAIL: $label: want '$want', got '$got'" >&2
    exit 1
  fi
}

# 1. -h / --help prints docstring, exit 0, reads no state
out="$("$repo/scripts/receipt" -h)"
echo "$out" | grep -q "Usage: scripts/receipt" || { echo "FAIL: help text: $out" >&2; exit 1; }
n=$((n + 1))

# 2. bad flag -> exit 2
rc=0; "$repo/scripts/receipt" --bogus >/dev/null 2>&1 || rc=$?
expect "bad flag exits 2" 2 "$rc"

# 3. Fixture repo
fx="$work/fx"
mkdir -p "$fx/scripts" "$fx/test"
cp "$repo/scripts/red-first" "$repo/scripts/receipt" "$fx/scripts/"
chmod +x "$fx/scripts/red-first" "$fx/scripts/receipt"
git -C "$fx" init -q
git -C "$fx" config user.email test@example.com
git -C "$fx" config user.name test
printf 'v1\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ngrep -q v1 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "chore: init"

# Case A: clean passing commit -> 4 lines, rc 0
printf 'v2\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\nset -e\ngrep -q v2 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "feat: upgrade v2"
rc=0; out="$(cd "$fx" && BP3_RECEIPT_GATE="echo gate-ok" ./scripts/receipt HEAD)" || rc=$?
expect "clean commit rc" 0 "$rc"
expect "4 lines printed" 4 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
echo "$out" | grep -q "^receipt .* feat: upgrade v2$" || { echo "FAIL: line 1: $out" >&2; exit 1; }
echo "$out" | grep -q "^check-full: rc=0 gate-ok$" || { echo "FAIL: line 2: $out" >&2; exit 1; }
echo "$out" | grep -q "^red-first: red (app)$" || { echo "FAIL: line 3: $out" >&2; exit 1; }
echo "$out" | grep -q "^tests: 1 file(s) changed (+2/-1 lines under test/)$" || { echo "FAIL: line 4: $out" >&2; exit 1; }
n=$((n + 4))

# Case B: dirty tree -> rc 2
printf 'dirty\n' >> "$fx/app.txt"
rc=0; (cd "$fx" && BP3_RECEIPT_GATE="echo gate-ok" ./scripts/receipt HEAD) >/dev/null 2>&1 || rc=$?
expect "dirty tree rc" 2 "$rc"
git -C "$fx" checkout -- app.txt

# Case C: failing red-first -> rc 1 with FAIL line
printf 'v3\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ntrue\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "feat: vacuous"
rc=0; out="$(cd "$fx" && BP3_RECEIPT_GATE="echo gate-ok" ./scripts/receipt HEAD)" || rc=$?
expect "vacuous receipt rc" 1 "$rc"
echo "$out" | grep -q "^red-first: FAIL " || { echo "FAIL: vacuous line: $out" >&2; exit 1; }
echo "$out" | grep -q "^tests: 1 file(s) changed (+1/-2 lines under test/)$" || { echo "FAIL: deleted lines count: $out" >&2; exit 1; }
n=$((n + 2))

# Case D: failing gate -> rc 1
rc=0; out="$(cd "$fx" && BP3_RECEIPT_GATE="echo boom; exit 1" ./scripts/receipt HEAD~1)" || rc=$?
expect "failing gate rc" 1 "$rc"
echo "$out" | grep -q "^check-full: rc=1 boom$" || { echo "FAIL: gate fail line: $out" >&2; exit 1; }
n=$((n + 1))

# Case E (manifest.2): [grade].gate in backpack.toml used when BP3_RECEIPT_GATE unset; env overrides manifest
printf 'version = 1\nrepo = "fx"\n\n[grade]\ngate = "echo backpack-gate" # comment\n' > "$fx/backpack.toml"
printf 'v4\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\nset -e\ngrep -q v4 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "feat: backpack gate"
rc=0; out="$(cd "$fx" && env -u BP3_RECEIPT_GATE ./scripts/receipt HEAD)" || rc=$?
expect "backpack gate rc" 0 "$rc"
echo "$out" | grep -q "^check-full: rc=0 backpack-gate$" || { echo "FAIL: backpack gate line: $out" >&2; exit 1; }
rc=0; out="$(cd "$fx" && BP3_RECEIPT_GATE="echo env-wins" ./scripts/receipt HEAD)" || rc=$?
expect "env overrides backpack gate rc" 0 "$rc"
echo "$out" | grep -q "^check-full: rc=0 env-wins$" || { echo "FAIL: env override line: $out" >&2; exit 1; }
n=$((n + 2))

echo "receipt tests: ok ($n assertions)"
