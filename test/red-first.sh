#!/usr/bin/env bash
# Fixture tests for scripts/red-first (fast-agy-induct verify.1).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-red-first-test.XXXXXX")"
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
out="$("$repo/scripts/red-first" -h)"
echo "$out" | grep -q "Usage: scripts/red-first" || { echo "FAIL: help text: $out" >&2; exit 1; }
n=$((n + 1))

# 2. bad flag -> exit 2
rc=0; "$repo/scripts/red-first" --bogus >/dev/null 2>&1 || rc=$?
expect "bad flag exits 2" 2 "$rc"

# 3. Fixture repo for real feat, vacuous feat, refactor, docs-only
fx="$work/fx"
mkdir -p "$fx/scripts" "$fx/test"
cp "$repo/scripts/red-first" "$fx/scripts/red-first"
chmod +x "$fx/scripts/red-first"
git -C "$fx" init -q
git -C "$fx" config user.email test@example.com
git -C "$fx" config user.name test
printf 'v1\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ngrep -q v1 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "chore: init"

# Case A: docs-only commit -> n/a, exit 0
printf 'readme\n' > "$fx/README.md"
git -C "$fx" add -A && git -C "$fx" commit -qm "docs: readme"
rc=0; out="$(cd "$fx" && ./scripts/red-first HEAD)" || rc=$?
expect "docs-only rc" 0 "$rc"
expect "docs-only line" "red-first: n/a (no test files changed)" "$out"

# Case B: real feat commit whose test fails on parent -> red, exit 0
printf 'v2\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ngrep -q v2 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "feat: upgrade to v2"
rc=0; out="$(cd "$fx" && ./scripts/red-first HEAD)" || rc=$?
expect "real feat rc" 0 "$rc"
expect "real feat line" "red-first: red (app)" "$out"

# Case C: vacuous test commit whose test passes on parent -> FAIL, exit 1
printf 'v3\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ntrue\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "feat: vacuous test"
rc=0; out="$(cd "$fx" && ./scripts/red-first HEAD)" || rc=$?
expect "vacuous test rc" 1 "$rc"
echo "$out" | grep -q "^red-first: FAIL (changed tests passed on parent " || { echo "FAIL: vacuous line: $out" >&2; exit 1; }
n=$((n + 1))

# Case D: refactor commit whose test stays green on parent -> green (refactor), exit 0
printf 'v3-refactored\n' > "$fx/app.txt"
printf '#!/usr/bin/env bash\ngrep -q v3 app.txt\n' > "$fx/test/app.sh"
chmod +x "$fx/test/app.sh"
git -C "$fx" add -A && git -C "$fx" commit -qm "refactor(app): tidy"
rc=0; out="$(cd "$fx" && ./scripts/red-first HEAD)" || rc=$?
expect "refactor rc" 0 "$rc"
expect "refactor line" "red-first: green (refactor)" "$out"

# Case E: no leaked git worktrees
wt_count="$(git -C "$fx" worktree list --porcelain | grep -c '^worktree ')"
expect "no leaked worktrees" 1 "$wt_count"

echo "red-first tests: ok ($n assertions)"
