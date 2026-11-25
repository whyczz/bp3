#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
sed 's/^max_cycles: .*/max_cycles: 1/' "$work/repo/plans/default.yaml" > "$work/repo/plans/default.yaml.tmp"; mv "$work/repo/plans/default.yaml.tmp" "$work/repo/plans/default.yaml"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
c() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 config "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
store="$work/repo/.git/bp3"

# --- help: documented flags, exit 0, no state read ---
out=$(c -h) || fail "config -h exit"
echo "$out" | grep -q -- "--format" || fail "config help names --format: $out"
[ ! -e "$store" ] || fail "config -h created the store"

# --- strict argv: dup, unknown, =-form, stray, bad format value ---
if out=$(c --source --source 2>&1); then fail "dup --source accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "dup --source code: $out"
if out=$(c --bogus 2>&1); then fail "unknown flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown flag code: $out"
if out=$(c --format=json 2>&1); then fail "--flag=value accepted"; fi
if out=$(c stray 2>&1); then fail "stray positional accepted"; fi
if out=$(c --format xml 2>&1); then fail "bad --format value accepted"; fi
[ ! -e "$store" ] || fail "usage errors created the store"

# --- outside a git repo: no store, typed refusal; help still works ---
mkdir -p "$work/nogit/bin"
cp "$root/bin/bp3" "$work/nogit/bin/"
if out=$(BP3_Q_BIN="$work/repo/g-bin" "$work/nogit/bin/bp3" config 2>&1); then fail "config outside git accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "outside-git code: $out"
BP3_Q_BIN="$work/repo/g-bin" "$work/nogit/bin/bp3" config -h >/dev/null || fail "config -h outside git"

# --- strictly read-only view: defaults, never creates .git/bp3/ ---
out=$(c)
echo "$out" | jq -e '.ok == true and .mode == "host" and .thresholds.setup_slow_s == 180 and .thresholds.depth_cap == 3 and .desks == []' \
  >/dev/null || fail "empty view: $out"
echo "$out" | jq -e '.config_dir | endswith(".git/bp3")' >/dev/null || fail "config_dir: $out"
[ ! -e "$store" ] || fail "read-only bp3 config created .git/bp3"
out=$(c --format table) || fail "config --format table exit"
echo "$out" | grep -q "thresholds" || fail "table view names thresholds: $out"

# --- read-only .git/ still succeeds (sandbox safety) ---
chmod 500 "$work/repo/.git"
out=$(c) || { chmod 700 "$work/repo/.git"; fail "read-only .git/ failed bp3 config"; }
chmod 700 "$work/repo/.git"
echo "$out" | jq -e '.ok == true' >/dev/null || fail "read-only .git/ verdict: $out"

# --- optional config.json thresholds are honored without writing ---
mkdir -p "$store"
printf '{"thresholds":{"setup_slow_s":42,"depth_cap":3}}\n' > "$store/config.json"
out=$(c)
echo "$out" | jq -e '.thresholds.setup_slow_s == 42 and .thresholds.depth_cap == 3' >/dev/null \
  || fail "edited threshold not honored: $out"
[ -z "$(git status --porcelain)" ] || fail "threshold edit dirtied git status"

# --- desks appear in config view ---
q c demo >/dev/null
BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness desk prepare demo node-1 --run D1 >/dev/null
out=$(c)
echo "$out" | jq -e '(.desks | length) == 1' >/dev/null || fail "desks view: $out"

# --- all worktrees resolve the same config_dir ---
git worktree add -q "$work/wt2" -b wt2
mkdir -p "$work/wt2/bin"
cp "$root/bin/bp3" "$work/wt2/bin/"
main_dir=$(c | jq -r .config_dir)
wt_dir=$(BP3_Q_BIN="$work/repo/g-bin" "$work/wt2/bin/bp3" config | jq -r .config_dir)
[ "$main_dir" = "$wt_dir" ] || fail "worktree config_dir differs: $main_dir vs $wt_dir"

# --- reserved config slug still refused ---
if out=$(q c config 2>&1); then fail "quest named config accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved config slug code: $out"

echo "config tests: ok"
